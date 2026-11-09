import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';
import '../widgets/listing_card.dart';
import '../widgets/running_out_strip.dart';

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key, required this.name});

  final String name;

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  static const double _cardHeight = ListingCard.browseHeight;
  static const double _loadMoreDistance = 400;
  static const SliverGridDelegate _gridLayout =
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: _cardHeight,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
      );

  final ScrollController _scroll = ScrollController();

  List<Listing>? _listings;
  List<Listing> _runningOut = const [];
  String? _error;
  String? _loadMoreError;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _page = 1;
  int _requestId = 0;

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

  Future<List<Listing>> _fetchRunningOut(ListingRepository repository) async {
    try {
      return await repository.fetchRunningOut();
    } on ApiException {
      return const [];
    }
  }

  Future<void> _load() async {
    final request = ++_requestId;
    final repository = context.read<ListingRepository>();
    final runningOut = _fetchRunningOut(repository);
    try {
      final first = await repository.fetchAvailable();
      final strip = await runningOut;
      if (!mounted || request != _requestId) return;
      setState(() {
        _listings = first.listings;
        _runningOut = strip;
        _hasMore = first.hasMore;
        _page = 1;
        _error = null;
        _loadMoreError = null;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _requestId) return;
      if (_listings == null) {
        setState(() => _error = e.message);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _retry() {
    setState(() {
      _listings = null;
      _error = null;
    });
    _load();
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    final request = _requestId;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final next = await context.read<ListingRepository>().fetchAvailable(
        page: _page + 1,
      );
      if (!mounted || request != _requestId) return;
      final seen = {for (final item in _listings!) item.id};
      setState(() {
        _listings = [
          ..._listings!,
          ...next.listings.where((item) => seen.add(item.id)),
        ];
        _hasMore = next.hasMore;
        _page += 1;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _loadMoreError = e.message;
        _loadingMore = false;
      });
    }
  }

  List<Widget> _feed(BuildContext context) {
    const sidePadding = EdgeInsets.symmetric(horizontal: AppSpacing.md);

    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                TextButton(onPressed: _retry, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      ];
    }

    final loaded = _listings;
    if (loaded == null) {
      return [
        SliverPadding(
          padding: sidePadding,
          sliver: SliverGrid.builder(
            gridDelegate: _gridLayout,
            itemCount: 4,
            itemBuilder: (context, index) => DecoratedBox(
              key: const ValueKey('listing-placeholder'),
              decoration: BoxDecoration(
                color: AppColors.field,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
        ),
      ];
    }

    final now = DateTime.now();
    final listings = [
      for (final item in loaded)
        if (item.isAvailableAt(now)) item,
    ];
    if (listings.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.fastfood_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'No food available right now',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Check back later for surplus food.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: sidePadding,
        sliver: SliverGrid.builder(
          gridDelegate: _gridLayout,
          itemCount: listings.length,
          itemBuilder: (context, index) =>
              ListingCard(listing: listings[index], showBadges: true),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _loadMoreFooter(),
        ),
      ),
    ];
  }

  Widget _loadMoreFooter() {
    if (_loadingMore) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _loadMoreError;
    if (error == null) return const SizedBox.shrink();
    return Column(
      children: [
        Text(error, textAlign: TextAlign.center),
        TextButton(onPressed: _loadMore, child: const Text('Try again')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final runningOut = [
      for (final item in _runningOut)
        if (item.isAvailableAt(now)) item,
    ];

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Greeting(name: widget.name),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      "Grab affordable meals before they're gone!",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
            if (runningOut.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                sliver: SliverToBoxAdapter(
                  child: _SectionTitle(
                    icon: Icons.local_fire_department,
                    color: AppColors.lowStock,
                    text: 'Running Out Soon',
                  ),
                ),
              ),
              SliverToBoxAdapter(child: RunningOutStrip(listings: runningOut)),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
            ],
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: _SectionTitle(
                  icon: Icons.new_releases,
                  color: theme.colorScheme.primary,
                  text: "What's New",
                ),
              ),
            ),
            ..._feed(context),
          ],
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String name;

  TextSpan _span(BuildContext context, String lead) => TextSpan(
    text: lead,
    children: [
      TextSpan(
        text: name,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w800);

    return LayoutBuilder(
      builder: (context, constraints) {
        final oneLine = _span(context, 'Welcome back, ');
        final painter = TextPainter(
          text: TextSpan(style: style, children: [oneLine]),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout(maxWidth: constraints.maxWidth);
        final fits = !painter.didExceedMaxLines;
        painter.dispose();

        return Text.rich(
          fits ? oneLine : _span(context, 'Welcome back,\n'),
          style: style,
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          text,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
