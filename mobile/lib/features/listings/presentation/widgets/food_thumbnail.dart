import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/theme/app_theme.dart';
import 'listing_image.dart';

class FoodThumbnail extends StatelessWidget {
  const FoodThumbnail({
    super.key,
    required this.category,
    this.size = 72,
    this.available = true,
    this.imageUrl,
  }) : fill = false;

  // A photo column [size] wide beside text: at least square, and as tall as
  // the text when the text is taller. Its width never depends on the text,
  // so the text can't be squeezed out of its row.
  const FoodThumbnail.fill({
    super.key,
    required this.category,
    this.size = fillSize,
    this.available = true,
    this.imageUrl,
  }) : fill = true;

  static const double fillSize = 88;

  final String? category;
  final String? imageUrl;
  final double size;
  final bool available;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final image = ListingImage(
      url: imageUrl,
      category: category,
      greyed: !available,
      iconSize: size * 0.45,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: fill
          ? PhotoColumn(width: size, child: image)
          : SizedBox.square(dimension: size, child: image),
    );
  }
}

// A box [width] wide and at least [width] tall that takes the full height a
// row stretches it to. It ignores the size of the photo inside, so a large
// photo can't change the row, and its width is fixed before the text beside
// it is measured.
class PhotoColumn extends SingleChildRenderObjectWidget {
  const PhotoColumn({super.key, required this.width, super.child});

  final double width;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPhotoColumn(width);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderPhotoColumn renderObject,
  ) => renderObject.width = width;
}

class RenderPhotoColumn extends RenderProxyBox {
  RenderPhotoColumn(this._width);

  double _width;

  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => _width;

  @override
  double computeMaxIntrinsicWidth(double height) => _width;

  @override
  double computeMinIntrinsicHeight(double width) => _width;

  @override
  double computeMaxIntrinsicHeight(double width) => _width;

  Size _sizeFor(BoxConstraints constraints) {
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : _width;
    return constraints.constrain(
      Size(_width, height < _width ? _width : height),
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _sizeFor(constraints);

  @override
  void performLayout() {
    size = _sizeFor(constraints);
    child?.layout(BoxConstraints.tight(size));
  }
}
