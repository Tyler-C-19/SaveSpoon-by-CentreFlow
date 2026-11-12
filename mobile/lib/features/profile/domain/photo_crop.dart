import 'dart:math' as math;
import 'dart:ui';

// The part of the original picture shown in the circle, as fractions of its
// width and height.
class PhotoCrop {
  const PhotoCrop({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  static const PhotoCrop whole = PhotoCrop(x: 0, y: 0, width: 1, height: 1);

  static PhotoCrop? fromJson(Object? json) {
    if (json is! Map) return null;
    double? read(String key) => (json[key] as num?)?.toDouble();
    final x = read('x');
    final y = read('y');
    final width = read('width');
    final height = read('height');
    if (x == null || y == null || width == null || height == null) return null;
    return PhotoCrop(x: x, y: y, width: width, height: height);
  }

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, double> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  Map<String, String> toFormFields() => {
    'cropX': '$x',
    'cropY': '$y',
    'cropWidth': '$width',
    'cropHeight': '$height',
  };

  bool sameAs(PhotoCrop? other, {double tolerance = 0.002}) =>
      other != null &&
      (x - other.x).abs() < tolerance &&
      (y - other.y).abs() < tolerance &&
      (width - other.width).abs() < tolerance &&
      (height - other.height).abs() < tolerance;
}

// Position and zoom of a picture inside a square frame of side [frame].
// At zoom 1 the picture just covers the frame.
class PicFrame {
  const PicFrame({
    required this.image,
    required this.frame,
    required this.zoom,
    required this.offset,
  });

  static const double maxZoom = 4;

  // Centred at zoom 1.
  factory PicFrame.centred(Size image, double frame) {
    final start = PicFrame(
      image: image,
      frame: frame,
      zoom: 1,
      offset: Offset.zero,
    );
    final shown = start.shownSize;
    return start.copyWith(
      offset: Offset((frame - shown.width) / 2, (frame - shown.height) / 2),
    );
  }

  factory PicFrame.fromCrop(PhotoCrop crop, Size image, double frame) {
    final cover = frame / math.min(image.width, image.height);
    final zoom = (frame / (crop.width * image.width * cover)).clamp(
      1.0,
      maxZoom,
    );
    final start = PicFrame(
      image: image,
      frame: frame,
      zoom: zoom,
      offset: Offset.zero,
    );
    final shown = start.shownSize;
    return start.copyWith(
      offset: Offset(-crop.x * shown.width, -crop.y * shown.height),
    );
  }

  final Size image;
  final double frame;
  final double zoom;

  // Top-left of the picture relative to the frame. Never positive, so the
  // picture always covers the frame.
  final Offset offset;

  double get _cover => frame / math.min(image.width, image.height);

  Size get shownSize =>
      Size(image.width * _cover * zoom, image.height * _cover * zoom);

  PicFrame copyWith({double? zoom, Offset? offset}) {
    final next = PicFrame(
      image: image,
      frame: frame,
      zoom: (zoom ?? this.zoom).clamp(1.0, maxZoom),
      offset: offset ?? this.offset,
    );
    final shown = next.shownSize;
    return PicFrame(
      image: image,
      frame: frame,
      zoom: next.zoom,
      offset: Offset(
        next.offset.dx.clamp(frame - shown.width, 0.0),
        next.offset.dy.clamp(frame - shown.height, 0.0),
      ),
    );
  }

  // Zooms while keeping the picture point under [focus] in place.
  PicFrame zoomAround(double newZoom, Offset focus) {
    final clamped = newZoom.clamp(1.0, maxZoom);
    final ratio = clamped / zoom;
    return copyWith(zoom: clamped, offset: focus - (focus - offset) * ratio);
  }

  PicFrame moveBy(Offset delta) => copyWith(offset: offset + delta);

  PhotoCrop toCrop() {
    final shown = shownSize;
    double fraction(double value) => value.clamp(0.0, 1.0);
    return PhotoCrop(
      x: fraction(-offset.dx / shown.width),
      y: fraction(-offset.dy / shown.height),
      width: fraction(frame / shown.width),
      height: fraction(frame / shown.height),
    );
  }
}
