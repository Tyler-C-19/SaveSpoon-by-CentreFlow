import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/photo_crop.dart';

// Shows the saved picture, an unsaved framed preview, or the initials.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.preview,
    this.previewCrop = PhotoCrop.whole,
    this.size = 96,
    this.isLoading = false,
  });

  final String name;
  final String? photoUrl;
  final ImageProvider? preview;
  final PhotoCrop previewCrop;
  final double size;

  // The green ring with a spinner while the profile is still loading, so the
  // initials don't flash before the picture.
  final bool isLoading;

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  Widget get _loading => Stack(
    alignment: Alignment.center,
    children: [
      CircleAvatar(radius: size / 2, backgroundColor: AppColors.primarySoft),
      SizedBox.square(
        dimension: size * 0.3,
        child: const CircularProgressIndicator(strokeWidth: 2.5),
      ),
    ],
  );

  // A green ring marks a profile picture, shown or loading.
  Widget _ring(Widget child) => Container(
    padding: const EdgeInsets.all(3),
    decoration: const BoxDecoration(
      color: AppColors.primary,
      shape: BoxShape.circle,
    ),
    child: child,
  );

  Widget get _initialsAvatar => CircleAvatar(
    radius: size / 2,
    backgroundColor: AppColors.primarySoft,
    foregroundColor: AppColors.primary,
    child: Text(
      _initials,
      style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final preview = this.preview;
    if (isLoading) return _ring(_loading);
    final Widget picture;
    if (preview != null) {
      picture = FramedImage(
        image: preview,
        crop: previewCrop,
        size: size,
        fallback: _initialsAvatar,
      );
    } else if (url != null) {
      // Keeps the last picture on screen until the next one is ready, and
      // shows the spinner, not the initials, while the first one loads.
      picture = ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                frame == null && !wasSynchronouslyLoaded ? _loading : child,
            errorBuilder: (_, _, _) => _initialsAvatar,
          ),
        ),
      );
    } else {
      return _initialsAvatar;
    }
    return _ring(picture);
  }
}

// Shows the [crop] part of [image] in a circle of [size].
class FramedImage extends StatelessWidget {
  const FramedImage({
    super.key,
    required this.image,
    required this.crop,
    required this.size,
    required this.fallback,
  });

  final ImageProvider image;
  final PhotoCrop crop;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final width = size / crop.width;
    final height = size / crop.height;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -crop.x * width,
              top: -crop.y * height,
              width: width,
              height: height,
              child: Image(
                image: image,
                fit: BoxFit.fill,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
