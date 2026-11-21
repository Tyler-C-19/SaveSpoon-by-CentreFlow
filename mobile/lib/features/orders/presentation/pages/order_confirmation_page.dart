import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../listings/domain/listing.dart';
import '../../../listings/presentation/widgets/food_thumbnail.dart';
import '../../../listings/presentation/widgets/listing_card.dart';
import '../../domain/order.dart';

class OrderConfirmationPage extends StatefulWidget {
  const OrderConfirmationPage({
    super.key,
    required this.orders,
    required this.onDone,
  });

  static const Duration animationTime = Duration(milliseconds: 1100);

  final List<Order> orders;
  final void Function(BuildContext context) onDone;

  @override
  State<OrderConfirmationPage> createState() => _OrderConfirmationPageState();
}

class _OrderConfirmationPageState extends State<OrderConfirmationPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OrderConfirmationPage.animationTime,
  )..forward();

  late final Animation<double> _circle = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.4, curve: Curves.elasticOut),
  );
  late final Animation<double> _tick = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
  );
  late final Animation<double> _content = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.6, 1, curve: Curves.easeOut),
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
    final orders = widget.orders;
    final total = orders.fold<double>(0, (sum, item) => sum + item.totalPrice);

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          orders.length == 1 ? 'Order placed!' : 'Orders placed!',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Pay at pickup. Please collect within the pickup time.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final order in orders) _OrderCard(order: order),
        if (orders.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text('Total', style: theme.textTheme.titleMedium),
                ),
                Text(
                  moneyLabel(total),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
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
                          animation: _tick,
                          builder: (context, _) => CustomPaint(
                            key: const ValueKey('order-placed-tick'),
                            painter: _TickPainter(
                              progress: _tick.value,
                              circleColor: colors.primary,
                              tickColor: colors.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FadeTransition(
                    opacity: _content,
                    child: SlideTransition(
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
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: AppButton(
                label: 'Back to Home',
                onPressed: () => widget.onDone(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter({
    required this.progress,
    required this.circleColor,
    required this.tickColor,
  });

  final double progress;
  final Color circleColor;
  final Color tickColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas.drawCircle(centre, size.width / 2, Paint()..color = circleColor);
    if (progress <= 0) return;

    final tick = Path()
      ..moveTo(size.width * 0.28, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.73, size.height * 0.37);
    final drawn = Path();
    var remaining = progress;
    for (final metric in tick.computeMetrics()) {
      final length = metric.length * remaining.clamp(0, 1);
      drawn.addPath(metric.extractPath(0, length), Offset.zero);
      remaining = 0;
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = tickColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.circleColor != circleColor ||
      oldDelegate.tickColor != tickColor;
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final address = order.pickupAddress;
    final name = Text(
      '${order.quantity} x ${order.itemName}',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium,
    );
    final priceStyle = theme.textTheme.titleMedium?.copyWith(
      color: colors.primary,
      fontWeight: FontWeight.w800,
    );
    final price = moneyLabel(order.totalPrice);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      // The photo is at least square and as tall as the text beside it.
      // The price sits beside the name, or under it when that would leave
      // the name less than half the text width.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textWidth =
              constraints.maxWidth - FoodThumbnail.fillSize - AppSpacing.sm;
          final priceWidth = (TextPainter(
            text: TextSpan(text: price, style: priceStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout()).width;
          final sideBySide =
              textWidth - priceWidth - AppSpacing.sm >= textWidth / 2;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FoodThumbnail.fill(
                  key: const ValueKey('order-photo'),
                  category: order.category,
                  imageUrl: order.imageThumbUrl,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sideBySide)
                        Row(
                          key: const ValueKey('order-price-beside'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: name),
                            const SizedBox(width: AppSpacing.sm),
                            Text(price, style: priceStyle),
                          ],
                        )
                      else ...[
                        name,
                        Text(
                          price,
                          key: const ValueKey('order-price-below'),
                          style: priceStyle,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      _Line(
                        icon: Icons.storefront_outlined,
                        text: order.stallName,
                      ),
                      if (address != null)
                        _Line(icon: Icons.location_on_outlined, text: address),
                      _Line(
                        icon: Icons.schedule,
                        text: pickupRangeLabel(
                          context,
                          order.pickupStart,
                          order.pickupEnd,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
