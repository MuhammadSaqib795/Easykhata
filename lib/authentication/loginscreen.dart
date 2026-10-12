import 'package:digitalkhata/authentication/auth_service.dart';
import 'package:digitalkhata/authentication/auth_widgets.dart';
import 'package:digitalkhata/authentication/forgot_password_screen.dart';
import 'package:digitalkhata/authentication/register_screen.dart';
import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/screens/mainscreen.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Opens the signed-in user's own data and replaces the auth flow with the
/// main screen. The signed-in user is automatically the backup owner.
Future<void> enterApp(BuildContext context, User user, {String? message}) async {
  await context.read<Dbprovider>().openForUser(user.uid);
  if (!context.mounted) return;
  // App-level messenger survives the route change below.
  final messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const Mainscreen()),
    (_) => false,
  );
  if (message != null) {
    messenger.showSnackBar(
      SnackBar(backgroundColor: AppColors.receivable, content: Text(message)),
    );
  }
}

/// Sign in with email/password or Google.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  bool get _busy => _loading || _googleLoading;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await AuthService.instance.signIn(
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      await enterApp(context, user);
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
      title: 'Welcome back',
      subtitle: 'Sign in to continue managing your khata.',
      footer: AuthSwitchLink(
        text: "Don't have an account?",
        action: 'Create account',
        onTap: _busy
            ? () {}
            : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RegisterScreen()),
              ),
      ),
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  hint: 'Enter your password',
                  controller: _password,
                  icon: Icons.lock_outline_rounded,
                  isPassword: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: AuthValidators.loginPassword,
                  onSubmitted: (_) => _signIn(),
                  enabled: !_busy,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ForgotPasswordScreen(
                                initialEmail: _email.text.trim(),
                              ),
                            ),
                          ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null) AuthErrorBanner(message: _error!),
                AuthPrimaryButton(
                  label: 'Sign in',
                  loadingLabel: 'Signing in…',
                  loading: _loading,
                  onPressed: _googleLoading ? null : _signIn,
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
