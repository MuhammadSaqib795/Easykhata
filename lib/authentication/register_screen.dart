import 'package:digitalkhata/authentication/auth_service.dart';
import 'package:digitalkhata/authentication/auth_widgets.dart';
import 'package:digitalkhata/authentication/loginscreen.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Create an Easy Khata account (Firebase email/password).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  bool get _busy => _loading || _googleLoading;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await AuthService.instance.register(
        fullName: _name.text,
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      await enterApp(
        context,
        user,
        message:
            'Account created. We sent a verification link to ${user.email}.',
      );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    if (_busy) return;
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      final user = await AuthService.instance.signInWithGoogle();
      if (user == null || !mounted) return;
      await enterApp(context, user);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      title: 'Create your account',
      subtitle: 'Start your digital khata in less than a minute.',
      footer: AuthSwitchLink(
        text: 'Already have an account?',
        action: 'Sign in',
        onTap: () => Navigator.of(context).maybePop(),
      ),
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthField(
                  label: 'Full name',
                  hint: 'e.g. Ali Khan',
                  controller: _name,
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  validator: AuthValidators.fullName,
                  enabled: !_busy,
                ),
                AuthField(
                  label: 'Email',
                  hint: 'you@example.com',
                  controller: _email,
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: AuthValidators.email,
                  enabled: !_busy,
                ),
                AuthField(
                  label: 'Password',
                  hint: 'At least 8 characters',
                  controller: _password,
                  icon: Icons.lock_outline_rounded,
                  isPassword: true,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: AuthValidators.newPassword,
                  onChanged: (_) => setState(() {}),
                  enabled: !_busy,
                ),
                PasswordStrengthBar(password: _password.text),
                AuthField(
                  label: 'Confirm password',
                  hint: 'Re-enter your password',
                  controller: _confirm,
                  icon: Icons.lock_outline_rounded,
                  isPassword: true,
                  textInputAction: TextInputAction.done,
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Please confirm your password.';
                    if (v != _password.text) return 'Passwords do not match.';
                    return null;
                  },
                  onSubmitted: (_) => _register(),
                  enabled: !_busy,
                ),
                const SizedBox(height: 4),
                if (_error != null) AuthErrorBanner(message: _error!),
                AuthPrimaryButton(
                  label: 'Create account',
                  loadingLabel: 'Creating account…',
                  loading: _loading,
                  onPressed: _googleLoading ? null : _register,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Your data is private to your account and backed up '
                  'automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
        const AuthOrDivider(),
        GoogleSignInButton(
          loading: _googleLoading,
          onPressed: _loading ? null : _google,
        ),
      ],
    );
  }
}
