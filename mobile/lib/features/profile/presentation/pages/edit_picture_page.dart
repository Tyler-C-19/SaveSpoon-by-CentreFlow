import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/error_text.dart';
import '../../data/photo_picker.dart';
import '../../data/profile_repository.dart';
import '../../domain/photo_crop.dart';
import '../../domain/user_profile.dart';
import '../widgets/picture_framer.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_heading.dart';

// The one place to add, frame, replace or remove the profile picture.
// Confirm saves straight away and closes with the saved profile; leaving
// without confirming changes nothing.
class EditPicturePage extends StatefulWidget {
  const EditPicturePage({
    super.key,
    required this.profile,
    this.photoPicker,
    this.sizer = decodeImageSize,
  });

  final UserProfile profile;
  final PhotoPicker? photoPicker;
  final ImageSizer sizer;

  @override
  State<EditPicturePage> createState() => _EditPicturePageState();
}

// What the page is showing: no picture, the saved one, or a new one.
enum _Shown { none, saved, fresh }

class _EditPicturePageState extends State<EditPicturePage> {
  late final PhotoPicker _picker = widget.photoPicker ?? DevicePhotoPicker();

  late _Shown _shown;
  PickedPhoto? _fresh;
  PhotoCrop _crop = PhotoCrop.whole;
  // The saved picture's framing as first shown, to tell whether it moved.
  PhotoCrop? _savedFraming;
  // Changes whenever a different picture is shown, so the frame starts over.
  int _version = 0;
  bool _isSaving = false;
  String? _error;

  UserProfile get _profile => widget.profile;

  bool get _hadPicture => _profile.photoUrl != null;

  @override
  void initState() {
    super.initState();
    _startOver();
  }

  void _startOver() {
    _shown = _hadPicture ? _Shown.saved : _Shown.none;
    _fresh = null;
    _crop = _profile.photoCrop ?? PhotoCrop.whole;
    _savedFraming = null;
    _version++;
    _error = null;
  }

  // Older pictures were saved without their original, so they can't be
  // framed again; a new picture can.
  bool get _canMove =>
      _shown == _Shown.fresh ||
      (_shown == _Shown.saved && _profile.canReframePhoto);

  ImageProvider? get _image => switch (_shown) {
    _Shown.none => null,
    _Shown.fresh => MemoryImage(Uint8List.fromList(_fresh!.bytes)),
    _Shown.saved => NetworkImage(
      _profile.photoOriginalUrl ?? _profile.photoUrl!,
    ),
  };

  bool get _hasChanges => switch (_shown) {
    _Shown.fresh => true,
    _Shown.none => _hadPicture,
    _Shown.saved =>
      _profile.canReframePhoto &&
          _savedFraming != null &&
          !_crop.sameAs(_savedFraming),
  };

  Future<void> _pick(PhotoSource source) async {
    setState(() => _error = null);
    final PickedPhoto? picked;
    try {
      picked = await _picker.pick(source);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't open the photo picker.");
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _shown = _Shown.fresh;
      _fresh = picked;
      _crop = PhotoCrop.whole;
      _version++;
    });
  }

  void _remove() => setState(() {
    _shown = _Shown.none;
    _fresh = null;
    _version++;
    _error = null;
  });

  void _undo() => setState(_startOver);

  Future<void> _confirm() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final repository = context.read<ProfileRepository>();
    final navigator = Navigator.of(context);
    try {
      final saved = switch (_shown) {
        _Shown.fresh => await repository.uploadPhoto(
          _fresh!.bytes,
          _fresh!.filename,
          _crop,
        ),
        _Shown.saved => await repository.reframePhoto(_crop),
        _Shown.none => await repository.removePhoto(),
      };
      // Loaded before closing, so the new picture shows at once.
      final url = saved.photoUrl;
      if (url != null && mounted) {
        await precacheImage(
          NetworkImage(url),
          context,
          onError: (_, _) {},
        ).timeout(const Duration(seconds: 10), onTimeout: () {});
      }
      navigator.pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _leave() async {
    final navigator = Navigator.of(context);
    if (_hasChanges) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text("Your new picture hasn't been saved."),
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
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final name = _profile.user.name;
    return PopScope<UserProfile>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileHeading(
                  title: 'Edit Profile Picture',
                  caption: _canMove
                      ? 'Drag to move. Pinch or use the slider to zoom.'
                      : image == null
                      ? 'Choose a picture or take a photo.'
                      : 'Choose a new picture to change the framing.',
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: Center(
                    child: image == null
                        ? _NoPicture(name: name)
                        : PictureFramer(
                            key: ValueKey(_version),
                            image: image,
                            // A new picture starts centred.
                            initialCrop: _shown == _Shown.fresh ? null : _crop,
                            canMove: _canMove,
                            sizer: widget.sizer,
                            onCrop: (crop) => setState(() {
                              _crop = crop;
                              if (_shown == _Shown.saved) {
                                _savedFraming ??= crop;
                              }
                            }),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    ProfileAvatar(
                      name: name,
                      preview: image,
                      previewCrop: _crop,
                      size: 64,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text(
                        'Preview',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _pick(PhotoSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose from Gallery'),
                    ),
                    TextButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _pick(PhotoSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take a Photo'),
                    ),
                    if (image != null)
                      TextButton.icon(
                        onPressed: _isSaving ? null : _remove,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove Picture'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ErrorText(_error),
                AppButton(
                  label: 'Confirm',
                  isLoading: _isSaving,
                  onPressed: _hasChanges ? _confirm : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: _hasChanges && !_isSaving ? _undo : null,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoPicture extends StatelessWidget {
  const _NoPicture({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProfileAvatar(name: name, size: 160),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'No profile picture',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// Opens the page. Returns the saved profile, or null if nothing was saved.
Future<UserProfile?> openEditPicture(
  BuildContext context,
  UserProfile profile, {
  PhotoPicker? photoPicker,
  ImageSizer sizer = decodeImageSize,
}) => Navigator.of(context).push<UserProfile>(
  MaterialPageRoute(
    builder: (_) => EditPicturePage(
      profile: profile,
      photoPicker: photoPicker,
      sizer: sizer,
    ),
  ),
);
