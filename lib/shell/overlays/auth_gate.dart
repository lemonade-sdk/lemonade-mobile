import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/exceptions.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_mode_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Local-first intro / sign-in gate. Option A is "Use Local AI" (the app's
/// default path, no account needed); option B — small text, "Don't have local
/// AI? Make an account" — expands the full subscription sign-in / register
/// form. Subscription stays fully wired to [authProvider].
///
/// The gate is mounted two ways: as the shell's full-screen overlay (no
/// callbacks — it just flips the mode) and as a pushed route ([SignInScreen]),
/// which passes [onUseLocal] / [onBack] to dismiss itself. Dismissal can't
/// rely on watching the mode flip: StateNotifier doesn't re-notify when the
/// new value equals the current one, so tapping "Use Local AI" while already
/// in local mode used to leave the route up and look like a dead button.
class AuthGate extends ConsumerStatefulWidget {
  /// Called after the mode flips to Local AI (in addition to the flip).
  final VoidCallback? onUseLocal;

  /// When set, the intro shows a Back button wired to this.
  final VoidCallback? onBack;

  const AuthGate({super.key, this.onUseLocal, this.onBack});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _register = false;
  bool _formOpen = false;
  bool _busy = false;
  bool _showPassword = false;
  String _segment = 'personal'; // account type picked at signup
  String? _error;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notifier = ref.read(authProvider.notifier);
      if (_register) {
        await notifier.register(
          clientName:
              _name.text.trim().isEmpty ? 'My account' : _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          segment: _segment,
        );
      } else {
        await notifier.login(
            email: _email.text.trim(), password: _password.text);
      }
    } catch (e) {
      if (!mounted) return;
      // On this screen a 401 means the credentials were wrong — not an
      // expired session.
      final msg = (e is LemonadeApiException && e.statusCode == 401)
          ? 'Email or password is incorrect.'
          : friendlyError(e,
              action: _register ? 'create your account' : 'sign in');
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Material(
      color: t.bg,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minHeight: MediaQuery.of(context).size.height - 80),
            child: _formOpen ? _buildForm(context) : _buildIntro(context),
          ),
        ),
      ),
    );
  }

  /// Option A: Local AI (primary, big). Option B: small text → the form.
  Widget _buildIntro(BuildContext context) {
    final t = context.nexus;
    return Column(
      children: [
        if (widget.onBack != null) ...[
          GestureDetector(
            onTap: widget.onBack,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 16, color: t.muted),
                  const SizedBox(width: 5),
                  Text('Back',
                      style: TextStyle(fontSize: 13, color: t.muted)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 40),
        const LemonLogo(size: 64),
        const SizedBox(height: 14),
        const LemonadeWordmark(fontSize: 23),
        const SizedBox(height: 6),
        Text('Local first. Subscription when you want it.',
            style: TextStyle(fontSize: 12.5, color: t.muted)),
        const SizedBox(height: 36),
        GestureDetector(
          onTap: () {
            ref.read(appModeProvider.notifier).setMode(AppMode.local);
            widget.onUseLocal?.call();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: BoxDecoration(
                color: t.accent, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                const Text('Use Local AI',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 3),
                Text('On your device or LAN — no account needed',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: () => setState(() {
            _register = true;
            _formOpen = true;
          }),
          behavior: HitTestBehavior.opaque,
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13.75),
              children: [
                TextSpan(text: 'Don\u2019t have local AI? ',
                    style: TextStyle(color: t.muted)),
                // Blue = tappable, matching the form's link color.
                TextSpan(text: 'Make an account',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: t.accent2)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() {
            _register = false;
            _formOpen = true;
          }),
          behavior: HitTestBehavior.opaque,
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13.75),
              children: [
                TextSpan(text: 'Or ', style: TextStyle(color: t.muted)),
                TextSpan(text: 'sign in to Subscription',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: t.accent2)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final t = context.nexus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            _formOpen = false;
            _error = null;
          }),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                Icon(Icons.arrow_back, size: 16, color: t.muted),
                const SizedBox(width: 5),
                Text('Back',
                    style: TextStyle(fontSize: 13, color: t.muted)),
              ],
            ),
          ),
        ),
        const LemonLogo(size: 40),
        const SizedBox(height: 12),
        Text(
            '${_register ? 'Create account' : 'Welcome back'} · Subscription',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
        const SizedBox(height: 20),
        if (_register) ...[
          NexusSegmented<String>(
            value: _segment,
            onChanged: (v) => setState(() => _segment = v),
            options: const [
              ('personal', 'Personal'),
              ('business', 'Business'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              _segment == 'personal'
                  ? 'Calling, AI automation & pay-as-you-go wallet.'
                  : 'Full PBX for teams — numbers, extensions & IVR.',
              style: TextStyle(fontSize: 11.5, color: t.muted)),
          const SizedBox(height: 12),
          _field(context, _name, 'Full name', Icons.person_outline),
          const SizedBox(height: 11),
        ],
        _field(context, _email, 'Email', Icons.mail_outline),
        const SizedBox(height: 11),
        _field(context, _password, 'Password', Icons.lock_outline,
            obscure: true),
        if (_error != null) ...[
          const SizedBox(height: 11),
          Text(_error!, style: TextStyle(fontSize: 12.5, color: t.danger)),
        ],
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _submit,
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
                color: t.accent, borderRadius: BorderRadius.circular(14)),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_register ? 'Create account' : 'Sign in',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_register ? 'Have an account?' : 'New here?',
                style: TextStyle(fontSize: 13, color: t.muted)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => setState(() => _register = !_register),
              child: Text(_register ? 'Sign in' : 'Create account',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.accent2)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(BuildContext context, TextEditingController c, String hint,
      IconData icon,
      {bool obscure = false}) {
    final t = context.nexus;
    return TextField(
      controller: c,
      obscureText: obscure && !_showPassword,
      style: TextStyle(fontSize: 15, color: t.text),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: t.faint),
        suffixIcon: obscure
            ? IconButton(
                icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: t.faint),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              )
            : null,
      ),
    );
  }
}
