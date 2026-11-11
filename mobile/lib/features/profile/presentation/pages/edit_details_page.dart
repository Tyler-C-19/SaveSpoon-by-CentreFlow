import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../../auth/domain/auth_validators.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/otp_input.dart';
import '../../../auth/presentation/widgets/resend_code_button.dart';
import '../../data/photo_picker.dart';
import '../../data/profile_repository.dart';
import '../../domain/user_profile.dart';
import '../widgets/picture_framer.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_heading.dart';
import 'edit_picture_page.dart';

// Closes with a ProfileChange for the profile page, or null when nothing
// changed.
class EditDetailsPage extends StatefulWidget {
  const EditDetailsPage({
    super.key,
    this.photoPicker,
    this.sizer = decodeImageSize,
  });

  static const String savedMessage = 'Account details updated.';
  static const String picMessage = 'Profile picture updated.';

  // Passed on to the Edit Profile Picture page.
  final PhotoPicker? photoPicker;
  final ImageSizer sizer;

  @override
  State<EditDetailsPage> createState() => _EditDetailsPageState();
}

class _EditDetailsPageState extends State<EditDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _emailBoxKey = GlobalKey();

  UserProfile? _profile;
  bool _isLoaded = false;
  bool _picSaved = false;
  bool _detailsSaved = false;
  String? _codeSentTo;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _name.text = user?.name ?? '';
    _phone.text = user?.phone ?? '';
    _email.text = user?.email ?? '';
    for (final field in [_name, _phone, _email]) {
      field.addListener(_refresh);
    }
    _loadProfile();
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final field in [_name, _phone, _email, _password, _code]) {
      field.dispose();
    }
    super.dispose();
  }

  // The form waits for this, so fields don't move once it loads.
  Future<void> _loadProfile() async {
    try {
      final profile = await context.read<ProfileRepository>().fetch();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _name.text = profile.user.name;
        _phone.text = profile.user.phone ?? '';
        _email.text = profile.user.email;
      });
    } on ApiException {
      // The form still opens, with email read-only.
    } finally {
      if (mounted) setState(() => _isLoaded = true);
    }
  }

  UserProfile? get _savedProfile => _profile;

  bool get _emailLocked => _savedProfile?.isLocked() ?? false;

  bool get _emailEdited =>
      (_savedProfile?.canChangeEmail ?? false) &&
      _email.text.trim().toLowerCase() != _currentEmail.toLowerCase();

  // An email edit in progress keeps its field and box when the lock starts,
  // so nothing on the page moves.
  bool get _canChangeEmail =>
      (_savedProfile?.canChangeEmail ?? false) &&
      (!_emailLocked || _emailEdited);

  bool get _lockedMidEdit => _emailLocked && _emailEdited;

  String get _currentEmail =>
      _savedProfile?.user.email ??
      context.read<AuthProvider>().user?.email ??
      '';

  bool get _emailChanged => _emailEdited && !_emailLocked;

  bool get _detailsChanged {
    final user = _savedProfile?.user ?? context.read<AuthProvider>().user;
    return _name.text.trim() != (user?.name ?? '') ||
        _phone.text.trim() != (user?.phone ?? '');
  }

  bool get _hasUnsavedChanges => _detailsChanged || _emailChanged;

  ProfileChange? _closingResult([String? message]) {
    final text =
        message ??
        (_detailsSaved
            ? EditDetailsPage.savedMessage
            : _picSaved
            ? EditDetailsPage.picMessage
            : null);
    return text == null ? null : ProfileChange(text, _profile);
  }

  // Updates the lock without touching what's been typed.
  Future<void> _refreshLock() async {
    try {
      final profile = await context.read<ProfileRepository>().fetch();
      if (mounted) setState(() => _profile = profile);
    } on ApiException {
      // The server still refuses while locked.
    }
  }

  // The picture page saves on its own Confirm.
  Future<void> _editPicture() async {
    final profile = _profile;
    if (profile == null) return;
    final saved = await openEditPicture(
      context,
      profile,
      photoPicker: widget.photoPicker,
      sizer: widget.sizer,
    );
    if (saved == null || !mounted) return;
    setState(() {
      _profile = saved;
      _picSaved = true;
    });
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final repository = context.read<ProfileRepository>();
    final navigator = Navigator.of(context);
    try {
      if (_detailsChanged) {
        _profile = await repository.updateDetails(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
        );
        _detailsSaved = true;
      }
      if (_emailChanged) {
        final email = _email.text.trim().toLowerCase();
        await repository.requestEmailChange(
          newEmail: email,
          currentPassword: _password.text,
        );
        _password.clear();
        if (!mounted) return;
        setState(() => _codeSentTo = email);
        // Keeps the code box in view rather than jumping to the top.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final box = _emailBoxKey.currentContext;
          if (box != null && box.mounted) {
            Scrollable.ensureVisible(
              box,
              duration: const Duration(milliseconds: 300),
              alignment: 0.2,
            );
          }
        });
        return;
      }
      // The profile page saves the new details once this page has closed.
      navigator.pop(_closingResult());
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 429) {
        // The email box shows the lock instead.
        setState(() => _error = null);
        await _refreshLock();
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _verify() async {
    final invalid = AuthValidators.code(_code.text);
    setState(() => _error = invalid);
    if (invalid != null) return;

    setState(() => _isSaving = true);
    final navigator = Navigator.of(context);
    try {
      _profile = await context.read<ProfileRepository>().verifyEmailChange(
        _code.text,
      );
      navigator.pop(
        _closingResult(
          '${EditDetailsPage.savedMessage} Your email is now $_codeSentTo.',
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Drops the pending email so its code stops working.
  Future<void> _keepCurrentEmail() async {
    setState(() => _isSaving = true);
    try {
      await context.read<ProfileRepository>().cancelEmailChange();
    } on ApiException {
      // The code still expires after 5 minutes.
    }
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _codeSentTo = null;
      _code.clear();
      _error = null;
      _email.text = _currentEmail;
    });
  }

  Future<void> _leave() async {
    final navigator = Navigator.of(context);
    if (_codeSentTo != null) {
      await _keepCurrentEmail();
      navigator.pop(_closingResult());
      return;
    }
    if (_hasUnsavedChanges) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text("Your changes haven't been saved."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    navigator.pop(_closingResult());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<ProfileChange>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: !_isLoaded
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ProfileHeading(
                          title: 'Edit Account Details',
                          caption: 'Update your name, phone, email and profile picture.',
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Center(
                          child: ValueListenableBuilder(
                            valueListenable: _name,
                            builder: (context, value, _) => ProfileAvatar(
                              name: value.text,
                              photoUrl: _profile?.photoUrl,
                            ),
                          ),
                        ),
                        Center(
                          child: TextButton.icon(
                            onPressed:
                                _isSaving ||
                                    _codeSentTo != null ||
                                    _profile == null
                                ? null
                                : _editPicture,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Edit Profile Picture'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ..._detailsForm(),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  // While a code is pending, the fields stay in place but can't be edited.
  List<Widget> _detailsForm() {
    const gap = SizedBox(height: AppSpacing.md);
    final pending = _codeSentTo != null;
    return [
      IgnorePointer(
        ignoring: pending,
        child: Opacity(
          opacity: pending ? 0.55 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Full name',
                icon: Icons.person_outline,
                controller: _name,
                validator: AuthValidators.name,
              ),
              gap,
              AppTextField(
                label: 'Phone number',
                icon: Icons.phone_outlined,
                controller: _phone,
                keyboardType: TextInputType.phone,
                validator: AuthValidators.phone,
              ),
              gap,
              if (_canChangeEmail)
                IgnorePointer(
                  ignoring: _lockedMidEdit,
                  child: AppTextField(
                    label: 'Email',
                    icon: Icons.email_outlined,
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: AuthValidators.email,
                  ),
                )
              else
                _ReadOnlyEmail(
                  email: _currentEmail,
                  note: _emailLocked
                      ? _lockNote(_savedProfile!)
                      : (_savedProfile?.isGoogleLinked ?? false)
                      ? "Linked to Google, so it can't be changed here."
                      : null,
                  isWarning: _emailLocked,
                ),
            ],
          ),
        ),
      ),
      if (_emailEdited) ...[
        gap,
        _EmailChangeBox(
          key: _emailBoxKey,
          currentEmail: _currentEmail,
          sentTo: _codeSentTo,
          lockNote: _lockedMidEdit
              ? '${_lockNote(_savedProfile!)} Keep your current email to '
                    'save other changes.'
              : null,
          onKeep: pending
              ? (_isSaving ? null : _keepCurrentEmail)
              : () => _email.text = _currentEmail,
          codeStep: pending
              ? [
                  OtpInput(controller: _code),
                  const SizedBox(height: AppSpacing.md),
                  ErrorText(_error),
                  AppButton(
                    label: 'Verify',
                    isLoading: _isSaving,
                    onPressed: _verify,
                  ),
                  ResendCodeButton(
                    onResend: context
                        .read<ProfileRepository>()
                        .resendEmailChange,
                  ),
                ]
              : const [],
        ),
        if (!pending) ...[
          gap,
          IgnorePointer(
            ignoring: _lockedMidEdit,
            child: Opacity(
              opacity: _lockedMidEdit ? 0.55 : 1,
              child: AppTextField(
                label: 'Current password',
                icon: Icons.lock_outline,
                controller: _password,
                isPassword: true,
                textInputAction: TextInputAction.done,
                validator: (value) => AuthValidators.required(
                  value,
                  'Enter your current password.',
                ),
              ),
            ),
          ),
        ],
      ],
      if (!pending) ...[
        const SizedBox(height: AppSpacing.lg),
        ErrorText(_error),
        AppButton(
          label: _emailEdited ? 'Save and Send Code' : 'Save Changes',
          isLoading: _isSaving,
          // Nothing to save until something changes, and nothing while a
          // locked email edit is still there.
          onPressed: _hasUnsavedChanges && !_lockedMidEdit ? _save : null,
        ),
      ],
    ];
  }

  String _lockNote(UserProfile profile) {
    final minutes = profile.lockMinutesLeft();
    return 'Email changes are locked for $minutes '
        'minute${minutes == 1 ? '' : 's'} after too many wrong password tries.';
  }
}

// Stays in the same place from editing the email through to the code.
class _EmailChangeBox extends StatelessWidget {
  const _EmailChangeBox({
    super.key,
    required this.currentEmail,
    required this.sentTo,
    required this.onKeep,
    required this.codeStep,
    this.lockNote,
  });

  final String currentEmail;
  final String? sentTo;

  // Replaces the explanation, in red, while locked.
  final String? lockNote;
  final VoidCallback? onKeep;
  final List<Widget> codeStep;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              lockNote != null
                  ? Icon(Icons.lock_clock_outlined, color: error)
                  : const Icon(Icons.info_outline, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  lockNote ??
                      (sentTo == null
                          ? "We'll email a code to the new address. You'll keep "
                                'using $currentEmail until you confirm it.'
                          : 'Code sent to $sentTo. Enter it within 5 minutes.'),
                  style: lockNote == null
                      ? null
                      : TextStyle(color: error, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (codeStep.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ...codeStep,
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onKeep,
              icon: const Icon(Icons.undo),
              label: Text(
                sentTo == null ? 'Keep Current Email' : 'Keep My Current Email',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyEmail extends StatelessWidget {
  const _ReadOnlyEmail({
    required this.email,
    this.note,
    this.isWarning = false,
  });

  final String email;
  final String? note;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.email_outlined, color: AppColors.textMuted),
      title: Text(email),
      subtitle: note == null
          ? null
          : Text(
              note!,
              style: isWarning
                  ? TextStyle(color: error, fontWeight: FontWeight.w600)
                  : null,
            ),
    );
  }
}
