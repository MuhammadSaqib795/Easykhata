import 'package:digitalkhata/authentication/auth_service.dart';
import 'package:digitalkhata/authentication/auth_widgets.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Sends Firebase's free password-reset e-mail.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);

  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return AuthScaffold(
        showBack: true,
        title: 'Check your email',
        subtitle:
            'If an account exists for ${_email.text.trim()}, we sent a link '
            'to reset your password. It may take a minute to arrive; check '
            'your spam folder too.',
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.mark_email_read_outlined, color: AppColors.receivable),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Password reset email sent.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF166534),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to sign in'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _sent = false),
            child: const Text('Use a different email'),
          ),
        ],
      );
    }

    return AuthScaffold(
      showBack: true,
      title: 'Reset your password',
      subtitle:
          "Enter the email you registered with and we'll send you a link to "
          'create a new password.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                label: 'Email',
                hint: 'you@example.com',
                controller: _email,
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                validator: AuthValidators.email,
                onSubmitted: (_) => _send(),
                enabled: !_loading,
              ),
              const SizedBox(height: 4),
              if (_error != null) AuthErrorBanner(message: _error!),
              AuthPrimaryButton(
                label: 'Send reset link',
                loadingLabel: 'Sending reset email…',
                loading: _loading,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
