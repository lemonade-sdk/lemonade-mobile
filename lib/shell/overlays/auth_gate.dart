import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/exceptions.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_mode_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Subscription-mode sign-in / register gate. Wired to [authProvider]. Wholly
/// optional — "Continue with Local AI" drops to local mode without an account.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _register = false;
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
          clientName: _name.text.trim().isEmpty ? 'My account' : _name.text.trim(),
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
            constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 80),
            child: Column(
              children: [
                const SizedBox(height: 40),
                const LemonLogo(size: 58),
                const SizedBox(height: 14),
                const LemonadeWordmark(fontSize: 23),
                const SizedBox(height: 4),
                Text('${_register ? 'Create account' : 'Welcome back'} · Subscription mode',
                    style: TextStyle(fontSize: 12.5, color: t.muted)),
                const SizedBox(height: 28),
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
                  Text(_error!,
                      style: TextStyle(fontSize: 12.5, color: t.danger)),
                ],
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _submit,
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                        color: t.accent,
                        borderRadius: BorderRadius.circular(14)),
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
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: () => ref
                      .read(appModeProvider.notifier)
                      .setMode(AppMode.local),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: t.line),
                    ),
                    child: Text('Continue with Local AI — no account needed',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.muted)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
                onPressed: () =>
                    setState(() => _showPassword = !_showPassword),
              )
            : null,
      ),
    );
  }
}
