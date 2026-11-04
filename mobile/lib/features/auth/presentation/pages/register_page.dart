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
import '../widgets/role_selector.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _role = 'customer';
  bool _acceptedTerms = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      setState(
        () => _error = 'Accept the Terms and Privacy Policy to continue.',
      );
      return;
    }
    setState(() => _isLoading = true);

    final email = _email.text.trim();
    try {
      final emailSent = await context.read<AuthProvider>().repository.register(
        role: _role,
        name: _name.text.trim(),
        email: email,
        phone: _phone.text.trim(),
        password: _password.text,
        acceptedTerms: _acceptedTerms,
      );
      if (!mounted) return;
      if (!emailSent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("We couldn't send your code. Resend it shortly."),
          ),
        );
      }
      context.pushReplacement(AppRoutes.verifyEmail, extra: email);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageLayout(
      title: 'Create your account',
      subtitle: 'Join SaveSpoon and help reduce food waste.',
      children: [
        RoleSelector(
          role: _role,
          onChanged: (role) => setState(() => _role = role),
        ),
        const SizedBox(height: AppSpacing.md),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Full name',
                icon: Icons.person_outline,
                controller: _name,
                autofillHints: const [AutofillHints.name],
                validator: AuthValidators.name,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Email',
                icon: Icons.mail_outline,
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: AuthValidators.email,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Phone number',
                icon: Icons.phone_outlined,
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                validator: AuthValidators.phone,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Password',
                icon: Icons.lock_outline,
                helper: AuthValidators.passwordRule,
                controller: _password,
                isPassword: true,
                autofillHints: const [AutofillHints.newPassword],
                validator: AuthValidators.password,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Confirm password',
                icon: Icons.lock_outline,
                controller: _confirm,
                isPassword: true,
                textInputAction: TextInputAction.done,
                validator: AuthValidators.confirms(() => _password.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          value: _acceptedTerms,
          onChanged: (value) => setState(() => _acceptedTerms = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text('I agree to the Terms and Privacy Policy'),
        ),
        const SizedBox(height: AppSpacing.sm),
        ErrorText(_error),
        AppButton(
          label: 'Create Account',
          isLoading: _isLoading,
          onPressed: _submit,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => context.go(AppRoutes.login),
          child: const Text('Already have an account? Log in'),
        ),
      ],
    );
  }
}
