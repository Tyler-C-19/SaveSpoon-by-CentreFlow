import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/auto_refresh.dart';
import '../../../../core/widgets/load_error.dart';
import '../../data/order_repository.dart';
import '../../domain/order.dart';
import '../widgets/order_card.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  static const Map<OrderTab, (String, String)> emptyText = {
    OrderTab.all: ('No orders yet', 'Orders you place will show here.'),
    OrderTab.upcoming: (
      'No upcoming orders',
      'Orders waiting for pickup will show here.',
    ),
    OrderTab.history: (
      'No past orders',
      'Collected, cancelled and ended orders will show here.',
    ),
  };

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with AutoRefresh {
  static const double _loadMoreDistance = 400;
  static const double _fade = 32;

  final ScrollController _scroll = ScrollController();

  OrderTab _tab = OrderTab.all;
  List<Order>? _orders;
  String? _error;
  String? _loadMoreError;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _page = 1;
  int _requestId = 0;
  // Older/Later buckets a customer has chosen to expand, keyed by the
  // first order in that run.
  final Set<String> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < _loadMoreDistance &&
        _loadMoreError == null) {
      _loadMore();
    }
  }

  @override
  Future<void> autoRefresh() async {
    if (_page == 1 && !_loadingMore) await _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    final request = ++_requestId;
    final tab = _tab;
    try {
      final first = await context.read<OrderRepository>().fetchOrders(tab: tab);
      if (!mounted || request != _requestId) return;
      setState(() {
        _orders = first.orders;
        _hasMore = first.hasMore;
        _page = 1;
        _error = null;
        _loadMoreError = null;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _requestId) return;
      if (_orders == null) {
        setState(() => _error = e.message);
      } else if (!silent) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    final request = _requestId;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final next = await context.read<OrderRepository>().fetchOrders(
        tab: _tab,
        page: _page + 1,
      );
      if (!mounted || request != _requestId) return;
      setState(() {
        _orders = [...?_orders, ...next.orders];
        _hasMore = next.hasMore;
        _page++;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = e.message;
      });
    }
  }

  void _showTab(OrderTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _orders = null;
      _error = null;
      _hasMore = false;
      _loadingMore = false;
      _expandedGroups.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  void _retry() {
    setState(() {
      _orders = null;
      _error = null;
    });
    _load();
  }

  // Coming back refreshes the list through AutoRefresh.
  void _openInfo(Order order) =>
      context.push<void>(AppRoutes.orderDetailsFor(order.id), extra: order);

  // Buckets by the same date the tab is sorted by (pickup date for
  // Upcoming, placed date otherwise), so same-day orders are always
  // adjacent and the header never has to repeat.
  DateTime _bucketDate(Order order) => _tab == OrderTab.upcoming
      ? order.pickupStart
      : (order.createdAt ?? order.pickupStart);

  // Runs of consecutive orders sharing one date bucket.
  List<(String, List<Order>)> _dateRuns(List<Order> orders, DateTime now) {
    final runs = <(String, List<Order>)>[];
    for (final order in orders) {
      final bucket = dateBucketLabel(_bucketDate(order), now);
      if (runs.isNotEmpty && runs.last.$1 == bucket) {
        runs.last.$2.add(order);
      } else {
        runs.add((bucket, [order]));
      }
    }
    return runs;
  }

  List<Widget> _orderCards(List<Order> orders, DateTime now) {
    final widgets = <Widget>[];
    for (final (bucket, run) in _dateRuns(orders, now)) {
      final groupKey = run.first.id;
      widgets.add(
        OrderDateHeader(key: ValueKey('order-date-$groupKey'), label: bucket),
      );
      if (collapsibleDateBuckets.contains(bucket) &&
          !_expandedGroups.contains(groupKey)) {
        widgets.add(
          OrderGroupSummary(
            key: ValueKey('order-group-$groupKey'),
            count: run.length,
            onTap: () => setState(() => _expandedGroups.add(groupKey)),
          ),
        );
        continue;
      }
      for (final order in run) {
        widgets.add(
          OrderCard(
            key: ValueKey('order-card-${order.id}'),
            order: order,
            now: now,
            onInfo: () => _openInfo(order),
          ),
        );
      }
    }
    return widgets;
  }

  // A labelled, sideways-scrolling row of single-choice chips, matching
  // the Vendor Listings sort row's style.
  Widget _tabChips() {
    return SingleChildScrollView(
      key: const ValueKey('order-tabs'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              'View:',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
          for (final tab in OrderTab.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(tab.label),
                selected: _tab == tab,
                onSelected: (_) => _showTab(tab),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final theme = Theme.of(context);
    final orders = _orders;
    if (orders == null) {
      final error = _error;
      return [
        const SizedBox(height: 96),
        Center(
          child: error == null
              ? const CircularProgressIndicator()
              : LoadError(message: error, onRetry: _retry),
        ),
      ];
    }
    if (orders.isEmpty) {
      final (title, caption) = OrdersPage.emptyText[_tab]!;
      return [
        const SizedBox(height: 96),
        Icon(
          Icons.receipt_long_outlined,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ];
    }

    final now = DateTime.now();
    return [
      ..._orderCards(orders, now),
      if (_loadingMore)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (_loadMoreError != null)
        Column(
          children: [
            Text(
              _loadMoreError!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            TextButton(onPressed: _loadMore, child: const Text('Try Again')),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The floating nav bar's height, given to the body by the tab shell.
    final navBar = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              MediaQuery.paddingOf(context).top + AppSpacing.md,
              AppSpacing.md,
              navBar + _fade + AppSpacing.md,
            ),
            children: [
              Text(
                'My Orders',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'View all your orders.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _tabChips(),
              const SizedBox(height: AppSpacing.md),
              ..._body(context),
            ],
          ),
        ),
        // Hides what scrolls behind the nav bar, with a soft edge above it.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: navBar + _fade,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.page.withValues(alpha: 0),
                    AppColors.page,
                    AppColors.page,
                  ],
                  stops: [0, _fade / (navBar + _fade), 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
