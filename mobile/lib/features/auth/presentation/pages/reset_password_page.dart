import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../domain/auth_validators.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_page_layout.dart';
import '../widgets/otp_input.dart';
import '../widgets/resend_code_button.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.email});

  final String email;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final invalidCode = AuthValidators.code(_code.text);
    setState(() => _error = invalidCode);
    final validForm = _formKey.currentState!.validate();
    if (invalidCode != null || !validForm) return;

    setState(() => _isLoading = true);
    try {
      await context.read<AuthProvider>().repository.resetPassword(
        email: widget.email,
        code: _code.text,
        newPassword: _password.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. Log in with your new password.'),
        ),
      );
      context.go(AppRoutes.login);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageLayout(
      title: 'Password Reset',
      subtitle: 'If ${widget.email} has an account, a code is on its way.',
      children: [
        OtpInput(controller: _code),
        const SizedBox(height: AppSpacing.sm),
        ResendCodeButton(
          onResend: () => context
              .read<AuthProvider>()
              .repository
              .forgotPassword(widget.email),
        ),
        const SizedBox(height: AppSpacing.sm),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'New password',
                icon: Icons.lock_outline,
                helper: AuthValidators.passwordRule,
                controller: _password,
                isPassword: true,
                autofillHints: const [AutofillHints.newPassword],
                validator: AuthValidators.password,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Retype password',
                icon: Icons.lock_outline,
                controller: _confirm,
                isPassword: true,
                textInputAction: TextInputAction.done,
                validator: AuthValidators.confirms(() => _password.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ErrorText(_error),
        AppButton(label: 'Confirm', isLoading: _isLoading, onPressed: _submit),
      ],
    );
  }
}
