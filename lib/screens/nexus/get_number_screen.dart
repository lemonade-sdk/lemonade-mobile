import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/exceptions.dart';
import '../../api/nexus/nexus_voice_models.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../providers/voice_providers.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_form.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// "Get a number" — search inventory, pick a product type (Personal / Business /
/// Both, business accounts only), and buy. The carrier is never shown: the user
/// only ever sees the product type and the price THIS account pays; the backend
/// resolves the provider. Requires the phone system enabled + org Admin/Owner
/// (any 403 → gated message).
class GetNumberScreen extends ConsumerStatefulWidget {
  const GetNumberScreen({super.key});

  @override
  ConsumerState<GetNumberScreen> createState() => _GetNumberScreenState();
}

class _GetNumberScreenState extends ConsumerState<GetNumberScreen> {
  final _digits = TextEditingController();
  final _state = TextEditingController();
  bool _byState = false;
  String _type = 'starts'; // starts | contains | ends

  // The switch is shown only when the server says so (Business accounts).
  bool _switchEnabled = false;
  String? _segment; // personal | business | both (null until switch is shown)

  bool _searching = false;
  bool _gated = false; // 403 — phone system not enabled / not an admin
  String? _error;
  List<NexusAvailableNumber>? _results;
  String? _buyingDid;

  @override
  void dispose() {
    _digits.dispose();
    _state.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _search() async {
    final client = ref.read(nexusVoiceClientProvider);
    if (client == null || _searching) return;
    final q = _digits.text.trim();
    final st = _state.text.trim().toUpperCase();
    if (!_byState && q.length < 3) {
      setState(() => _error = 'Enter at least 3 digits (an area code works).');
      return;
    }
    if (_byState && st.length != 2) {
      setState(() => _error = 'Enter a 2-letter state code (e.g. CA).');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _gated = false;
    });
    try {
      final res = await client.searchAvailable(
        query: _byState ? null : q,
        state: _byState ? st : null,
        type: _type,
        segment: _switchEnabled ? _segment : null,
      );
      if (!mounted) return;
      setState(() {
        _results = res.numbers;
        _switchEnabled = res.switchEnabled;
        if (res.switchEnabled) {
          _segment ??= res.segment.isEmpty ? 'both' : res.segment;
        } else {
          _segment = null;
        }
      });
    } on UnauthorizedException {
      setState(() => _gated = true);
    } on ServerException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _buy(NexusAvailableNumber n) async {
    final label = await _confirmBuy(n);
    if (label == null) return; // cancelled ('' = buy without a label)
    final client = ref.read(nexusVoiceClientProvider);
    if (client == null) return;
    setState(() => _buyingDid = n.number);
    try {
      await client.orderNumber(n.number, label: label);
      ref.invalidate(voiceNumbersProvider);
      _toast('Number added.');
      if (mounted) Navigator.of(context).pop(true);
    } on UnauthorizedException {
      _toast("Your phone system isn't enabled, or you need an admin.");
    } on ServerException catch (e) {
      switch (e.statusCode) {
        case 402:
          await _addFunds();
        case 400:
          _toast("That number isn't available anymore — searching again.");
          _search();
        case 409:
          _toast('That number is already on the platform.');
        default:
          _toast(e.message);
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _buyingDid = null);
    }
  }

  /// Confirm + optional label. Returns the label ('' = none), or null if cancelled.
  Future<String?> _confirmBuy(NexusAvailableNumber n) {
    final t = context.nexus;
    final ctrl = TextEditingController();
    final where = [
      if (n.rateCenter.isNotEmpty) n.rateCenter,
      if (n.state.isNotEmpty) n.state,
    ].join(', ');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg2,
        title: Text('Buy ${_fmt(n.number)}?',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${n.priceLabel}${where.isEmpty ? '' : ' · $where'}',
                style: TextStyle(color: t.muted, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: TextStyle(fontSize: 14, color: t.text),
              decoration: nexusInput(context, 'Label (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: t.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text('Buy ${n.priceLabel}',
                  style: TextStyle(color: t.accent2))),
        ],
      ),
    );
  }

  /// 402 insufficient_balance → open the wallet top-up, then they retry the buy.
  Future<void> _addFunds() async {
    final t = context.nexus;
    final amt = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: t.bg2,
        title: Text('Add funds to your wallet',
            style: TextStyle(color: t.text, fontSize: 16)),
        children: [
          for (final a in [500, 1000, 2000])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: Text('\$${a ~/ 100}.00',
                  style: TextStyle(color: t.text, fontSize: 15)),
            ),
        ],
      ),
    );
    if (amt == null) return;
    final client = ref.read(nexusBillingClientProvider);
    if (client == null) return;
    try {
      final url = await client.topup(amt);
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      _toast('Finish in the browser, then buy the number again.');
    } catch (e) {
      _toast('$e');
    }
  }

  String _fmt(String e164) {
    final d = e164.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 11 && d.startsWith('1')) {
      return '+1 (${d.substring(1, 4)}) ${d.substring(4, 7)}-${d.substring(7)}';
    }
    if (d.length == 10) {
      return '(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
    }
    return e164;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return NexusPage(
      title: 'Get a number',
      body: _gated
          ? _gate(context)
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              children: [
                _searchCard(context),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: t.danger, fontSize: 12.5)),
                ],
                const SizedBox(height: 18),
                ..._resultsSection(context),
              ],
            ),
    );
  }

  Widget _gate(BuildContext context) {
    final t = context.nexus;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, color: t.muted, size: 34),
            const SizedBox(height: 12),
            Text('Phone system not available',
                style: TextStyle(
                    color: t.text, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                'Numbers need the phone system enabled and an organization '
                'Admin or Owner. Ask an admin, or enable the phone package in '
                'Plan & wallet.\n\nJust bought a phone plan? Setup runs '
                'automatically and takes a couple of minutes — then retry.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted, fontSize: 13, height: 1.45)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                setState(() => _gated = false);
                _search();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                    color: t.accent, borderRadius: BorderRadius.circular(11)),
                child: const Text('Retry',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchCard(BuildContext context) {
    final t = context.nexus;
    return NexusCard(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NexusSegmented<bool>(
            options: const [(false, 'Area code'), (true, 'State')],
            value: _byState,
            onChanged: (v) => setState(() => _byState = v),
          ),
          const SizedBox(height: 14),
          if (!_byState) ...[
            NexusField(
              label: 'Area code or digits',
              controller: _digits,
              hint: 'e.g. 415',
              keyboard: TextInputType.number,
            ),
            Row(children: [
              Text('MATCH',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: t.faint)),
              const SizedBox(width: 12),
              Expanded(
                child: NexusSegmented<String>(
                  options: const [
                    ('starts', 'Starts'),
                    ('contains', 'Contains'),
                    ('ends', 'Ends'),
                  ],
                  value: _type,
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),
            ]),
          ] else
            NexusField(
              label: 'State',
              controller: _state,
              hint: 'e.g. CA',
              keyboard: TextInputType.text,
            ),
          if (_switchEnabled) ...[
            const SizedBox(height: 14),
            Text('NUMBER TYPE',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: t.faint)),
            const SizedBox(height: 6),
            NexusSegmented<String>(
              options: const [
                ('personal', 'Personal'),
                ('business', 'Business'),
                ('both', 'Both'),
              ],
              value: _segment ?? 'both',
              onChanged: (v) {
                setState(() => _segment = v);
                _search();
              },
            ),
          ],
          const SizedBox(height: 16),
          NexusButton(label: 'Search', busy: _searching, onTap: _search),
        ],
      ),
    );
  }

  List<Widget> _resultsSection(BuildContext context) {
    final t = context.nexus;
    final results = _results;
    if (results == null) {
      return [
        Text('Search by area code or state to find an available number.',
            style: TextStyle(color: t.muted, fontSize: 12.5)),
      ];
    }
    if (results.isEmpty) {
      return [
        NexusCard(
          radius: 14,
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('No numbers match — try another area code or state.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted, fontSize: 13)),
          ),
        ),
      ];
    }
    return [
      NexusSectionLabel('Available · ${results.length}'),
      const SizedBox(height: 10),
      for (final n in results) ...[
        _resultRow(context, n),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _resultRow(BuildContext context, NexusAvailableNumber n) {
    final t = context.nexus;
    final busy = _buyingDid == n.number;
    final where = [
      if (n.rateCenter.isNotEmpty) n.rateCenter,
      if (n.state.isNotEmpty) n.state,
    ].join(', ');
    return NexusCard(
      radius: 14,
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_fmt(n.number),
                  style: nexusMono(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.text)),
              const SizedBox(height: 3),
              Text('${n.priceLabel}${where.isEmpty ? '' : ' · $where'}',
                  style: TextStyle(fontSize: 11.5, color: t.muted)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: busy ? null : () => _buy(n),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
                color: t.accent, borderRadius: BorderRadius.circular(11)),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Buy',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}
