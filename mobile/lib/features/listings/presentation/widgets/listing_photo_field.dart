import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/error_text.dart';
import '../../../profile/data/photo_picker.dart';
import '../../../profile/domain/photo_crop.dart';
import '../../../profile/presentation/widgets/picture_framer.dart';
import '../../domain/listing.dart';
import '../pages/frame_photo_page.dart';
import 'listing_image.dart';

// What saving the form will do with the listing's photo.
class ListingPhotoDraft {
  const ListingPhotoDraft._({
    this.fresh,
    this.freshImage,
    this.crop,
    this.removed = false,
  });

  // Leave the saved photo (or no photo) as it is.
  static const keep = ListingPhotoDraft._();
  static const removal = ListingPhotoDraft._(removed: true);

  factory ListingPhotoDraft.fresh(PickedPhoto photo, PhotoCrop crop) =>
      ListingPhotoDraft._(
        fresh: photo,
        freshImage: MemoryImage(Uint8List.fromList(photo.bytes)),
        crop: crop,
      );

  factory ListingPhotoDraft.reframed(PhotoCrop crop) =>
      ListingPhotoDraft._(crop: crop);

  final PickedPhoto? fresh;
  // Kept once, so redrawing doesn't decode the photo again.
  final MemoryImage? freshImage;
  final PhotoCrop? crop;
  final bool removed;

  bool get isChange => fresh != null || crop != null || removed;
}

// The "Upload Image Here" box at the top of Add a Listing and Edit Listing.
class ListingPhotoField extends StatefulWidget {
  const ListingPhotoField({
    super.key,
    required this.draft,
    required this.onChanged,
    this.saved,
    this.category,
    this.enabled = true,
    this.photoPicker,
    this.sizer = decodeImageSize,
  });

  final ListingPhotoDraft draft;
  final ValueChanged<ListingPhotoDraft> onChanged;
  // The listing being edited, for its saved photo.
  final Listing? saved;
  final String? category;
  final bool enabled;
  final PhotoPicker? photoPicker;
  final ImageSizer sizer;

  @override
  State<ListingPhotoField> createState() => _ListingPhotoFieldState();
}

class _ListingPhotoFieldState extends State<ListingPhotoField> {
  late final PhotoPicker _picker = widget.photoPicker ?? DevicePhotoPicker();
  String? _error;

  ListingPhotoDraft get _draft => widget.draft;

  bool get _hasSaved => widget.saved?.imageUrl != null;

  bool get _showsPhoto =>
      _draft.fresh != null || (!_draft.removed && _hasSaved);

  // The original and framing that "Adjust Framing" starts from.
  (ImageProvider, PhotoCrop?)? get _framingSource {
    final fresh = _draft.freshImage;
    if (fresh != null) return (fresh, _draft.crop);
    final saved = widget.saved;
    if (_draft.removed || saved == null || !saved.canReframePhoto) return null;
    return (
      listingPhotoProvider(saved.imageOriginalUrl!),
      _draft.crop ?? saved.imageCrop,
    );
  }

  Future<void> _choose() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, PhotoSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(context, PhotoSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _error = null);

    final PickedPhoto? picked;
    try {
      picked = await _picker.pick(source);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't open the photo picker.");
      return;
    }
    if (picked == null || !mounted) return;
    final image = MemoryImage(Uint8List.fromList(picked.bytes));
    final crop = await openFramePhoto(context, image, sizer: widget.sizer);
    if (crop == null || !mounted) return;
    widget.onChanged(ListingPhotoDraft.fresh(picked, crop));
  }

  Future<void> _adjust() async {
    final source = _framingSource;
    if (source == null) return;
    final crop = await openFramePhoto(
      context,
      source.$1,
      initialCrop: source.$2,
      sizer: widget.sizer,
    );
    if (crop == null || !mounted) return;
    final fresh = _draft.fresh;
    if (fresh != null) {
      return widget.onChanged(ListingPhotoDraft.fresh(fresh, crop));
    }
    // Back to the saved framing counts as no change.
    widget.onChanged(
      crop.sameAs(widget.saved?.imageCrop)
          ? ListingPhotoDraft.keep
          : ListingPhotoDraft.reframed(crop),
    );
  }

  void _remove() => widget.onChanged(
    _hasSaved ? ListingPhotoDraft.removal : ListingPhotoDraft.keep,
  );

  Widget _photo() {
    final fresh = _draft.freshImage;
    if (fresh != null) return _CroppedImage(image: fresh, crop: _draft.crop!);
    final saved = widget.saved!;
    final crop = _draft.crop;
    if (crop != null && saved.imageOriginalUrl != null) {
      return _CroppedImage(
        image: listingPhotoProvider(saved.imageOriginalUrl!),
        crop: crop,
      );
    }
    return ListingImage(url: saved.imageUrl, category: widget.category);
  }

  Widget _empty(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.field,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_a_photo_outlined, size: 40, color: colors.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Upload Image Here',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: colors.primary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'JPEG, PNG or WebP, up to 5 MB.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showsPhoto = _showsPhoto;
    final canAdjust = _framingSource != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: Listing.photoAspect,
          child: PhotoBorder(
            show: showsPhoto,
            radius: AppRadius.lg,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const ValueKey('listing-photo-box'),
                onTap: widget.enabled && !showsPhoto ? _choose : null,
                child: showsPhoto ? _photo() : _empty(context),
              ),
            ),
          ),
        ),
        if (showsPhoto)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: widget.enabled ? _choose : null,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Change Photo'),
              ),
              if (canAdjust)
                TextButton.icon(
                  onPressed: widget.enabled ? _adjust : null,
                  icon: const Icon(Icons.crop),
                  label: const Text('Adjust Framing'),
                ),
              TextButton.icon(
                onPressed: widget.enabled ? _remove : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove Photo'),
              ),
            ],
          ),
        if (_error case final message?) ...[
          const SizedBox(height: AppSpacing.sm),
          ErrorText(message),
        ],
      ],
    );
  }
}

// Shows only the framed part of [image], filling the box.
class _CroppedImage extends StatelessWidget {
  const _CroppedImage({required this.image, required this.crop});

  final ImageProvider image;
  final PhotoCrop crop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / crop.width;
        final height = constraints.maxHeight / crop.height;
        return ClipRect(
          child: Stack(
            children: [
              Positioned(
                left: -crop.x * width,
                top: -crop.y * height,
                width: width,
                height: height,
                child: Image(
                  key: const ValueKey('listing-photo-preview'),
                  image: image,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: AppColors.field),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
