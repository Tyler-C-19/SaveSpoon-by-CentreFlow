import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../data/vendor_repository.dart';
import '../../domain/vendor_validators.dart';

class ProfileBanner extends StatefulWidget {
  const ProfileBanner({super.key});

  @override
  State<ProfileBanner> createState() => _ProfileBannerState();
}

class _ProfileBannerState extends State<ProfileBanner> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final description = await context
          .read<VendorRepository>()
          .fetchDescription();
      if (mounted) setState(() => _visible = description.trim().isEmpty);
    } on ApiException {
      if (mounted) setState(() => _visible = false);
    }
  }

  Future<void> _openForm() async {
    final repository = context.read<VendorRepository>();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => _DescriptionSheet(repository: repository),
    );
    if (saved == true && mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Material(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openForm,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.edit_note),
                const SizedBox(width: AppSpacing.sm),
                const Expanded(
                  child: Text('Add a description so customers know you better.'),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _visible = false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DescriptionSheet extends StatefulWidget {
  const _DescriptionSheet({required this.repository});

  final VendorRepository repository;

  @override
  State<_DescriptionSheet> createState() => _DescriptionSheetState();
}

class _DescriptionSheetState extends State<_DescriptionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter a description.';
    return VendorValidators.description(value);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await widget.repository.updateDescription(_description.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Description',
              icon: Icons.notes_outlined,
              controller: _description,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              validator: _validate,
            ),
            const SizedBox(height: AppSpacing.md),
            ErrorText(_error),
            AppButton(label: 'Save', isLoading: _isLoading, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
