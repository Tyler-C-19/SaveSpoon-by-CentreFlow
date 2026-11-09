import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/error_text.dart';
import '../../domain/auth_validators.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_page_layout.dart';
import '../widgets/otp_input.dart';
import '../widgets/resend_code_button.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, required this.email});

  final String email;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final _code = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final invalid = AuthValidators.code(_code.text);
    setState(() => _error = invalid);
    if (invalid != null) return;

    setState(() => _isLoading = true);
    try {
      await context.read<AuthProvider>().verifyEmail(widget.email, _code.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageLayout(
      title: 'Verification',
      subtitle: 'A one-time code was sent to ${widget.email}.',
      children: [
        OtpInput(controller: _code),
        const SizedBox(height: AppSpacing.lg),
        ErrorText(_error),
        AppButton(label: 'Verify', isLoading: _isLoading, onPressed: _submit),
        const SizedBox(height: AppSpacing.sm),
        ResendCodeButton(
          onResend: () => context
              .read<AuthProvider>()
              .repository
              .resendVerification(widget.email),
        ),
      ],
    );
  }
}
