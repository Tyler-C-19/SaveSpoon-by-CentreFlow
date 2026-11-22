import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../profile/domain/photo_crop.dart';
import '../../../profile/presentation/widgets/picture_framer.dart';
import '../../../profile/presentation/widgets/profile_heading.dart';
import '../../domain/listing.dart';

// Frames a listing photo in 4:3. Confirm returns the framing; Back returns null.
class FramePhotoPage extends StatefulWidget {
  const FramePhotoPage({
    super.key,
    required this.image,
    this.initialCrop,
    this.sizer = decodeImageSize,
  });

  final ImageProvider image;
  final PhotoCrop? initialCrop;
  final ImageSizer sizer;

  @override
  State<FramePhotoPage> createState() => _FramePhotoPageState();
}

class _FramePhotoPageState extends State<FramePhotoPage> {
  PhotoCrop? _crop;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ProfileHeading(
                title: 'Adjust Photo',
                caption: 'Drag to move. Pinch or use the slider to zoom.',
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Center(
                  child: PictureFramer(
                    image: widget.image,
                    initialCrop: widget.initialCrop,
                    sizer: widget.sizer,
                    aspect: Listing.photoAspect,
                    round: false,
                    onCrop: (crop) => setState(() => _crop = crop),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Confirm',
                onPressed: _crop == null
                    ? null
                    : () => Navigator.of(context).pop(_crop),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<PhotoCrop?> openFramePhoto(
  BuildContext context,
  ImageProvider image, {
  PhotoCrop? initialCrop,
  ImageSizer sizer = decodeImageSize,
}) => Navigator.of(context).push<PhotoCrop>(
  MaterialPageRoute(
    builder: (_) =>
        FramePhotoPage(image: image, initialCrop: initialCrop, sizer: sizer),
  ),
);
