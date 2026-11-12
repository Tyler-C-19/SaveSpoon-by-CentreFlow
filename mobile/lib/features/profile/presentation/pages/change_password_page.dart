import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../../auth/domain/auth_validators.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/profile_repository.dart';
import '../widgets/profile_heading.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  static const String doneMessage =
      'Password changed. All other active sessions have been logged out.';

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _differs(String? value) => value == _current.text
      ? 'Choose a password different from your current one.'
      : AuthValidators.password(value);

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    try {
      final token = await context.read<ProfileRepository>().changePassword(
        currentPassword: _current.text,
        newPassword: _password.text,
      );
      await auth.replaceToken(token);
      navigator.pop(ChangePasswordPage.doneMessage);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const ProfileHeading(
                title: 'Change Password',
                caption: 'All other active sessions will be logged out.',
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Current password',
                icon: Icons.lock_outline,
                controller: _current,
                isPassword: true,
                autofillHints: const [AutofillHints.password],
                validator: (value) => AuthValidators.required(
                  value,
                  'Enter your current password.',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'New password',
                icon: Icons.lock_outline,
                helper: AuthValidators.passwordRule,
                controller: _password,
                isPassword: true,
                autofillHints: const [AutofillHints.newPassword],
                validator: _differs,
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
              const SizedBox(height: AppSpacing.lg),
              ErrorText(_error),
              AppButton(
                label: 'Confirm',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
