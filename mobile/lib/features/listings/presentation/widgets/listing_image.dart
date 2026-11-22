import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/listing.dart';
import 'category_picker.dart';

// Listing photos are kept on the phone after the first download, so a photo
// already seen shows at once and isn't downloaded again. Tests swap in a
// plain network loader.
ImageProvider Function(String url) listingPhotoProvider =
    CachedNetworkImageProvider.new;

// Starts downloading the full photo as a card is tapped, so the details page
// has it sooner. It is the same photo that page loads, so nothing extra is used.
void preloadListingPhoto(BuildContext context, Listing listing) {
  final url = listing.imageUrl;
  if (url == null) return;
  precacheImage(listingPhotoProvider(url), context, onError: (_, _) {});
}

// A listing's photo filling its box (cropped from the middle), with the
// category icon when there is none or it fails. While a large photo loads,
// [placeholderUrl] (usually the card-sized copy, already downloaded) shows
// under a small spinner.
class ListingImage extends StatelessWidget {
  const ListingImage({
    super.key,
    required this.url,
    required this.category,
    this.placeholderUrl,
    this.greyed = false,
    this.greyColor = AppColors.field,
    this.iconSize = 48,
    this.showIcon = true,
    this.showLoading = true,
  });

  final String? url;
  final String? placeholderUrl;
  final String? category;
  // Unlisted or unavailable: a grey wash over the photo.
  final bool greyed;
  final Color greyColor;
  final double iconSize;
  // False leaves the plain background, for boxes with their own content.
  final bool showIcon;
  // A small spinner while the photo downloads.
  final bool showLoading;

  @override
  Widget build(BuildContext context) {
    final iconBox = DecoratedBox(
      decoration: BoxDecoration(
        color: greyed ? greyColor : null,
        gradient: greyed
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryPale, AppColors.primarySoft],
              ),
      ),
      child: showIcon
          ? Center(
              child: Icon(
                categoryIcon(category),
                size: iconSize,
                color: greyed
                    ? AppColors.textMuted
                    : Theme.of(context).colorScheme.primary,
              ),
            )
          : const SizedBox.expand(),
    );
    final address = url;
    if (address == null || address.isEmpty) return iconBox;

    final early = placeholderUrl;
    final photo = Image(
      image: listingPhotoProvider(address),
      key: const ValueKey('listing-photo'),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null) return child;
        if (!showLoading) return const SizedBox.shrink();
        return Center(
          child: SizedBox.square(
            key: const ValueKey('listing-photo-loading'),
            dimension: iconSize < 48 ? 18 : 24,
            child: const CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      },
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    final layers = Stack(
      fit: StackFit.expand,
      children: [
        iconBox,
        if (early != null && early != address)
          Image(
            image: listingPhotoProvider(early),
            key: const ValueKey('listing-photo-early'),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        photo,
      ],
    );
    if (!greyed) return layers;
    return Stack(
      fit: StackFit.expand,
      children: [
        layers,
        IgnorePointer(
          child: ColoredBox(
            key: const ValueKey('listing-photo-grey'),
            color: greyColor.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

// A green border around a listing photo, like the profile picture's ring.
// Without a photo the box is only rounded.
class PhotoBorder extends StatelessWidget {
  const PhotoBorder({
    super.key,
    required this.show,
    required this.radius,
    required this.child,
  });

  static const double width = 3;

  final bool show;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
    if (!show) return clipped;
    return Container(
      key: const ValueKey('photo-border'),
      padding: const EdgeInsets.all(width),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(radius + width),
      ),
      child: clipped,
    );
  }
}
