import 'package:flutter/material.dart';

import '../widgets/listing_image.dart';

// A listing photo on its own, full screen, with pinch to zoom.
class PhotoViewPage extends StatelessWidget {
  const PhotoViewPage({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.inverseSurface,
      appBar: AppBar(
        backgroundColor: colors.inverseSurface,
        foregroundColor: colors.onInverseSurface,
        title: Text(title),
      ),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image(
              image: listingPhotoProvider(url),
              key: const ValueKey('full-photo'),
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : CircularProgressIndicator(color: colors.onInverseSurface),
              errorBuilder: (_, _, _) => Text(
                "Couldn't load this photo.",
                style: TextStyle(color: colors.onInverseSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> openPhotoView(BuildContext context, String url, String title) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewPage(url: url, title: title),
      ),
    );
