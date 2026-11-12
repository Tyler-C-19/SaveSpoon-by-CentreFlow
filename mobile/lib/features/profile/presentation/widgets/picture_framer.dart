import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/photo_crop.dart';

// Finds a picture's size. Tests pass their own.
typedef ImageSizer = Future<Size?> Function(
  BuildContext context,
  ImageProvider image,
);

Future<Size?> decodeImageSize(BuildContext context, ImageProvider image) {
  final done = Completer<Size?>();
  final stream = image.resolve(createLocalImageConfiguration(context));
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!done.isCompleted) {
        done.complete(
          Size(info.image.width.toDouble(), info.image.height.toDouble()),
        );
      }
    },
    onError: (_, _) {
      stream.removeListener(listener);
      if (!done.isCompleted) done.complete(null);
    },
  );
  stream.addListener(listener);
  return done.future;
}

// Move and zoom [image] inside a circle that fills the available square.
// Reports the chosen crop whenever it changes, including once at the start.
class PictureFramer extends StatefulWidget {
  const PictureFramer({
    super.key,
    required this.image,
    required this.onCrop,
    this.initialCrop,
    this.canMove = true,
    this.sizer = decodeImageSize,
  });

  final ImageProvider image;
  final PhotoCrop? initialCrop;
  final ValueChanged<PhotoCrop> onCrop;
  final bool canMove;
  final ImageSizer sizer;

  @override
  State<PictureFramer> createState() => _PictureFramerState();
}

class _PictureFramerState extends State<PictureFramer> {
  static const double _sliderHeight = 56;

  Size? _imageSize;
  bool _failed = false;
  PicFrame? _frame;
  double _gestureStartZoom = 1;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    widget.sizer(context, widget.image).then((size) {
      if (!mounted) return;
      setState(() {
        _imageSize = size;
        _failed = size == null || size.isEmpty;
      });
    });
  }

  PicFrame _frameFor(double side) {
    final current = _frame;
    if (current != null && current.frame == side) return current;
    final image = _imageSize!;
    final initial = current?.toCrop() ?? widget.initialCrop;
    final frame = initial == null
        ? PicFrame.centred(image, side)
        : PicFrame.fromCrop(initial, image, side);
    if (current == null) {
      // The starting crop, once the picture's size is known.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCrop(frame.toCrop());
      });
    }
    return _frame = frame;
  }

  void _update(PicFrame frame) {
    setState(() => _frame = frame);
    widget.onCrop(frame.toCrop());
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(child: Text("Couldn't open this picture."));
    }
    if (_imageSize == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(
          80.0,
          math.min(
            constraints.maxWidth,
            constraints.maxHeight - (widget.canMove ? _sliderHeight : 0),
          ),
        );
        final frame = _frameFor(side);
        final shown = frame.shownSize;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onScaleStart: widget.canMove
                  ? (_) => _gestureStartZoom = _frame!.zoom
                  : null,
              onScaleUpdate: widget.canMove
                  ? (details) => _update(
                      _frame!
                          .zoomAround(
                            _gestureStartZoom * details.scale,
                            details.localFocalPoint,
                          )
                          .moveBy(details.focalPointDelta),
                    )
                  : null,
              child: SizedBox.square(
                dimension: side,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Stack(
                    children: [
                      Positioned(
                        left: frame.offset.dx,
                        top: frame.offset.dy,
                        width: shown.width,
                        height: shown.height,
                        child: Image(
                          image: widget.image,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: AppColors.primarySoft),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _CircleMask(
                              shade: colors.scrim.withValues(alpha: 0.55),
                              ring: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.canMove)
              SizedBox(
                height: _sliderHeight,
                width: side,
                child: Row(
                  children: [
                    const Icon(Icons.zoom_out),
                    Expanded(
                      child: Slider(
                        value: frame.zoom,
                        min: 1,
                        max: PicFrame.maxZoom,
                        label: 'Zoom',
                        onChanged: (value) => _update(
                          frame.zoomAround(value, Offset(side / 2, side / 2)),
                        ),
                      ),
                    ),
                    const Icon(Icons.zoom_in),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// Shades everything outside the circle that becomes the profile picture.
class _CircleMask extends CustomPainter {
  const _CircleMask({required this.shade, required this.ring});

  final Color shade;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromLTWH(0, 0, size.width, size.height);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(circle),
      Path()..addOval(circle),
    );
    canvas.drawPath(outside, Paint()..color = shade);
    canvas.drawOval(
      circle.deflate(1.5),
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_CircleMask oldDelegate) =>
      oldDelegate.shade != shade || oldDelegate.ring != ring;
}
