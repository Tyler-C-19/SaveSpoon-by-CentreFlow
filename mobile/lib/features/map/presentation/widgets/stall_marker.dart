import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// A drawn pin and the point of its image that sits on the stall.
typedef StallIcon = ({BitmapDescriptor icon, Offset anchor});

// A teardrop map pin in the theme's colour with the stall's item count in a
// white circle, and optionally a name label under it. Drawn once per count,
// label and size.
class StallMarkerIcons {
  StallMarkerIcons({
    required this.fill,
    required this.onFill,
    required this.labelText,
    required this.labelFill,
  });

  static const double width = 36;
  static const double height = 48;
  static const double labelMaxWidth = 160;
  // Room around the pin for its shadow.
  static const double _margin = 4;
  static const double _labelGap = 2;
  static const double _labelPadding = 4;

  final Color fill;
  final Color onFill;
  final Color labelText;
  final Color labelFill;
  final Map<(int, String?, double, double), Future<StallIcon>> _drawn = {};

  static String countLabel(int count) => count > 99 ? '99+' : '$count';

  // Where the pin's tip sits in an image without a label.
  static Offset get anchor =>
      const Offset(0.5, (height + _margin) / (height + _margin * 2));

  // The pin outline: a circle tapering to a point at the bottom.
  static Path pinPath(double scale) {
    final radius = width / 2 * scale;
    final tip = height * scale;
    final centre = Offset(radius, radius);
    final angle = math.acos(radius / (tip - radius));
    return Path()
      ..moveTo(radius, tip)
      ..lineTo(
        centre.dx + radius * math.cos(math.pi / 2 + angle),
        centre.dy + radius * math.sin(math.pi / 2 + angle),
      )
      ..arcTo(
        Rect.fromCircle(center: centre, radius: radius),
        math.pi / 2 + angle,
        2 * math.pi - 2 * angle,
        false,
      )
      ..close();
  }

  // [name] and [distance] make the label under the pin; no label without a
  // name.
  Future<StallIcon> icon(
    int count, {
    String? name,
    String? distance,
    required double scale,
    required double pixelRatio,
  }) {
    final label = name == null
        ? null
        : distance == null
        ? name
        : '$name\u0000$distance';
    return _drawn[(count, label, scale, pixelRatio)] ??= _draw(
      count,
      name,
      distance,
      scale,
      pixelRatio,
    );
  }

  TextPainter? _labelPainter(String? name, String? distance, double scale) {
    if (name == null) return null;
    final style = TextStyle(
      color: labelText,
      fontSize: 12 * scale,
      fontWeight: FontWeight.w700,
    );
    return TextPainter(
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: name),
          if (distance != null)
            TextSpan(
              text: ' · $distance',
              style: style.copyWith(color: fill),
            ),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: labelMaxWidth * scale);
  }

  Future<StallIcon> _draw(
    int count,
    String? name,
    String? distance,
    double scale,
    double pixelRatio,
  ) async {
    final margin = _margin * scale;
    final pinWidth = width * scale;
    final pinHeight = height * scale;
    final label = _labelPainter(name, distance, scale);
    final labelPadding = _labelPadding * scale;
    final labelSize = label == null
        ? Size.zero
        : Size(label.width + labelPadding * 3, label.height + labelPadding * 2);
    final size = Size(
      math.max(pinWidth, labelSize.width) + margin * 2,
      pinHeight +
          margin * 2 +
          (label == null ? 0 : _labelGap * scale + labelSize.height),
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    final pinLeft = (size.width - pinWidth) / 2;
    canvas.save();
    canvas.translate(pinLeft, margin);
    final radius = pinWidth / 2;
    final centre = Offset(radius, radius);
    final pin = pinPath(scale);
    canvas.drawShadow(pin, Colors.black, 2 * scale, false);
    canvas.drawPath(pin, Paint()..color = fill);
    canvas.drawCircle(centre, radius * 0.68, Paint()..color = onFill);
    final text = TextPainter(
      text: TextSpan(
        text: countLabel(count),
        style: TextStyle(
          color: fill,
          fontSize: (count > 99 ? 10 : 14) * scale,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, centre - Offset(text.width / 2, text.height / 2));
    text.dispose();
    canvas.restore();

    if (label != null) {
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (size.width - labelSize.width) / 2,
          margin + pinHeight + _labelGap * scale,
          labelSize.width,
          labelSize.height,
        ),
        Radius.circular(labelSize.height / 2),
      );
      canvas.drawShadow(Path()..addRRect(box), Colors.black, scale, false);
      canvas.drawRRect(box, Paint()..color = labelFill);
      label.paint(
        canvas,
        Offset(box.left + labelPadding * 1.5, box.top + labelPadding),
      );
      label.dispose();
    }

    final image = await recorder.endRecording().toImage(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return (
      icon: BitmapDescriptor.bytes(
        bytes!.buffer.asUint8List(),
        imagePixelRatio: pixelRatio,
      ),
      anchor: Offset(0.5, (margin + pinHeight) / size.height),
    );
  }
}
