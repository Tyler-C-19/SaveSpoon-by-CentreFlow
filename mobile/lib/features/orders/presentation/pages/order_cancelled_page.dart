import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/order.dart';
import 'order_confirmation_page.dart'
    show OrderConfirmationPage, OrderSummaryCard;

// Slides in like Order Placed, so the X animates in view.
Route<void> orderCancelledRoute(OrderCancelledPage page) =>
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondary) => page,
      transitionsBuilder: (context, animation, secondary, child) =>
          SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                ),
            child: child,
          ),
    );

class OrderCancelledPage extends StatefulWidget {
  const OrderCancelledPage({
    super.key,
    required this.cancelled,
    required this.onDone,
    this.skipped = const [],
  });

  final List<Order> cancelled;
  final List<Order> skipped;
  final void Function(BuildContext context) onDone;

  @override
  State<OrderCancelledPage> createState() => _OrderCancelledPageState();
}

class _OrderCancelledPageState extends State<OrderCancelledPage>
    with SingleTickerProviderStateMixin {
  // Same timing as the Order Placed tick.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OrderConfirmationPage.animationTime,
  )..forward();

  late final Animation<double> _circle = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.4, curve: Curves.elasticOut),
  );
  late final Animation<double> _cross = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
  );
  late final Animation<double> _content = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.6, 1, curve: Curves.easeOut),
  );

  // Fades in with the details; nothing can be tapped until the X is done.
  Widget _afterAnimation(Widget child) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) =>
        IgnorePointer(ignoring: !_controller.isCompleted, child: child),
    child: FadeTransition(opacity: _content, child: child),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textMuted,
    );
    final cancelled = widget.cancelled;
    final skipped = widget.skipped;
    final several = cancelled.length > 1;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          several ? 'Orders Cancelled' : 'Order Cancelled',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          several
              ? 'No payment was taken, as these orders were pay at pickup.'
              : 'No payment was taken, as this order was pay at pickup.',
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final order in cancelled) OrderSummaryCard(order: order),
        if (skipped.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Still Ordered', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "These couldn't be cancelled, usually because pickup "
            'has started. Please collect them as planned.',
            style: muted,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final order in skipped) OrderSummaryCard(order: order),
        ],
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Center(
                    child: ScaleTransition(
                      scale: _circle,
                      child: SizedBox.square(
                        dimension: 80,
                        child: AnimatedBuilder(
                          animation: _cross,
                          builder: (context, _) => CustomPaint(
                            key: const ValueKey('order-cancelled-mark'),
                            painter: _CrossPainter(
                              progress: _cross.value,
                              circleColor: colors.error,
                              crossColor: colors.onError,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _afterAnimation(
                    SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.05),
                        end: Offset.zero,
                      ).animate(_content),
                      child: details,
                    ),
                  ),
                ],
              ),
            ),
            _afterAnimation(
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: AppButton(
                  label: 'Back to My Orders',
                  onPressed: () => widget.onDone(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Draws the two strokes of the X one after the other.
class _CrossPainter extends CustomPainter {
  const _CrossPainter({
    required this.progress,
    required this.circleColor,
    required this.crossColor,
  });

  final double progress;
  final Color circleColor;
  final Color crossColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas.drawCircle(centre, size.width / 2, Paint()..color = circleColor);
    if (progress <= 0) return;

    final paint = Paint()
      ..color = crossColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round;
    final low = size.width * 0.33;
    final high = size.width * 0.67;
    final strokes = [
      (Offset(low, low), Offset(high, high)),
      (Offset(high, low), Offset(low, high)),
    ];
    for (var index = 0; index < strokes.length; index++) {
      final part = (progress * strokes.length - index).clamp(0.0, 1.0);
      if (part <= 0) break;
      final (start, end) = strokes[index];
      canvas.drawLine(start, Offset.lerp(start, end, part)!, paint);
    }
  }

  @override
  bool shouldRepaint(_CrossPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.circleColor != circleColor ||
      oldDelegate.crossColor != crossColor;
}
