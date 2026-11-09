import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_validators.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_page_layout.dart';
import '../widgets/role_selector.dart';

class CompleteGooglePage extends StatefulWidget {
  const CompleteGooglePage({super.key, required this.profile});

  final GoogleProfile profile;

  @override
  State<CompleteGooglePage> createState() => _CompleteGooglePageState();
}

class _CompleteGooglePageState extends State<CompleteGooglePage> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  String _role = 'customer';
  bool _acceptedTerms = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
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
    try {
      await context.read<AuthProvider>().completeGoogleSignUp(
        profile: widget.profile,
        role: _role,
        phone: _phone.text.trim(),
        acceptedTerms: _acceptedTerms,
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final who = profile.name.isEmpty
        ? profile.email
        : '${profile.name} (${profile.email})';

    return AuthPageLayout(
      title: 'Almost there',
      subtitle: 'Signing up as $who.',
      children: [
        RoleSelector(
          role: _role,
          onChanged: (role) => setState(() => _role = role),
        ),
        const SizedBox(height: AppSpacing.md),
        Form(
          key: _formKey,
          child: AppTextField(
            label: 'Phone number',
            icon: Icons.phone_outlined,
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.done,
            validator: AuthValidators.phone,
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
          label: 'Finish signing up',
          isLoading: _isLoading,
          onPressed: _submit,
        ),
      ],
    );
  }
}
