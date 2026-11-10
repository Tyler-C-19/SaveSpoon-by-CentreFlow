import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/auto_refresh.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/listing_repository.dart';
import '../../data/recent_searches.dart';
import '../../domain/listing.dart';
import '../providers/listing_changes.dart';
import '../widgets/category_picker.dart';
import '../widgets/search_result_row.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.store = const SecureRecentSearchStore()});

  static const Duration typingPause = Duration(milliseconds: 150);
  static const int maxLength = 50;

  final RecentSearchStore store;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with AutoRefresh {
  static const double _loadMoreDistance = 400;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  late final ListingChanges _changes;
  late final String _accountId;
  Timer? _typing;

  String _query = '';
  List<Listing>? _results;
  List<Listing> _otherStalls = const [];
  List<String> _recent = const [];
  String? _error;
  String? _loadMoreError;
  bool _searching = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _page = 1;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _accountId = context.read<AuthProvider>().user?.id ?? '';
    _scroll.addListener(_onScroll);
    _changes = context.read<ListingChanges>();
    _changes.addListener(_refresh);
    _loadRecent();
  }

  @override
  void dispose() {
    _typing?.cancel();
    _changes.removeListener(_refresh);
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static String _clean(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _loadRecent() async {
    try {
      final saved = await widget.store.read(_accountId);
      if (mounted) setState(() => _recent = saved);
    } catch (_) {
      // Recent searches are a convenience, so a storage failure shows none.
    }
  }

  void _saveRecent(List<String> updated) {
    setState(() => _recent = updated);
    widget.store.write(_accountId, updated).catchError((_) {});
  }

  void _remember(String term) => _saveRecent(withRecentSearch(_recent, term));

  void _forget(String term) => _saveRecent([
    for (final item in _recent)
      if (item != term) item,
  ]);

  void _onChanged(String text) {
    _typing?.cancel();
    final term = _clean(text);
    if (term.isEmpty) {
      _showStart();
      return;
    }
    setState(() {});
    _typing = Timer(SearchPage.typingPause, () => _search(term));
  }

  void _onSubmitted(String text) {
    _typing?.cancel();
    final term = _clean(text);
    if (term.isEmpty) return;
    _remember(term);
    _search(term);
  }

  void _searchFor(String term, {bool remember = true}) {
    _typing?.cancel();
    _controller.text = term;
    _focus.unfocus();
    if (remember) _remember(term);
    _search(term);
  }

  void _clear() {
    _typing?.cancel();
    _controller.clear();
    _showStart();
  }

  void _showStart() {
    _requestId++;
    setState(() {
      _query = '';
      _results = null;
      _otherStalls = const [];
      _error = null;
      _loadMoreError = null;
      _searching = false;
      _hasMore = false;
      _loadingMore = false;
    });
  }

  // Earlier results stay on screen while the next search loads.
  Future<void> _search(String term, {bool silent = false}) async {
    final request = ++_requestId;
    if (!silent) {
      setState(() {
        _query = term;
        _searching = true;
        _error = null;
        _loadMoreError = null;
      });
    }
    try {
      final found = await context.read<ListingRepository>().search(term);
      if (!mounted || request != _requestId) return;
      setState(() {
        _results = found.listings;
        _otherStalls = found.otherStalls;
        _hasMore = found.hasMore;
        _page = 1;
        _searching = false;
        _error = null;
        _loadMoreError = null;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _requestId) return;
      if (silent) return;
      setState(() {
        _searching = false;
        _results = null;
        _otherStalls = const [];
        _error = e.message;
      });
    }
  }

  Future<void> _refresh() async {
    if (_query.isEmpty) return;
    if (_results == null) return _search(_query);
    final request = _requestId;
    try {
      final found = await context.read<ListingRepository>().search(_query);
      if (!mounted || request != _requestId) return;
      setState(() {
        _results = found.listings;
        _otherStalls = found.otherStalls;
        _hasMore = found.hasMore;
        _page = 1;
        _loadMoreError = null;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _requestId) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Future<void> autoRefresh() async {
    if (_query.isNotEmpty &&
        _page == 1 &&
        !_loadingMore &&
        !_searching &&
        _results != null) {
      await _search(_query, silent: true);
    }
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < _loadMoreDistance &&
        _loadMoreError == null) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _searching || _results == null) return;
    final request = _requestId;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final next = await context.read<ListingRepository>().search(
        _query,
        page: _page + 1,
      );
      if (!mounted || request != _requestId) return;
      final seen = {for (final item in _results!) item.id};
      setState(() {
        _results = [
          ..._results!,
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

  Future<void> _open(Listing listing) async {
    _focus.unfocus();
    if (_query.isNotEmpty) _remember(_query);
    final message = await context.push<String>(
      AppRoutes.foodDetailsFor(listing.id),
    );
    // Returning to this screen also refreshes it through AutoRefresh.
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    await _refresh();
  }

  List<Listing> _available(List<Listing> listings) {
    final now = DateTime.now();
    return [
      for (final item in listings)
        if (item.isAvailableAt(now)) item,
    ];
  }

  Widget _searchBox() {
    return TextField(
      key: const ValueKey('search-box'),
      controller: _controller,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      inputFormatters: [LengthLimitingTextInputFormatter(SearchPage.maxLength)],
      onChanged: _onChanged,
      onSubmitted: _onSubmitted,
      decoration: InputDecoration(
        hintText: 'Search by food or vendor',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searching && _results != null)
                    const SizedBox.square(
                      key: ValueKey('search-progress'),
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: _clear,
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _startSlivers(BuildContext context) {
    final theme = Theme.of(context);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        sliver: SliverToBoxAdapter(
          child: _SectionTitle(
            icon: Icons.category_outlined,
            color: theme.colorScheme.primary,
            text: 'Browse by Category',
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: _CategoryTile.size,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: ListingOptions.categories.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final category = ListingOptions.categories[index];
              return _CategoryTile(
                category: category,
                onTap: () => _searchFor(category, remember: false),
              );
            },
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      if (_recent.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SectionTitle(
                        icon: Icons.history,
                        color: theme.colorScheme.primary,
                        text: 'Recent Searches',
                      ),
                    ),
                    TextButton(
                      onPressed: () => _saveRecent(const []),
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final term in _recent)
                      _RecentPill(
                        key: ValueKey('recent-$term'),
                        term: term,
                        onTap: () => _searchFor(term),
                        onRemove: () => _forget(term),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _rows(List<Listing> listings) => [
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      sliver: SliverList.separated(
        itemCount: listings.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) => SearchResultRow(
          listing: listings[index],
          onTap: () => _open(listings[index]),
        ),
      ),
    ),
  ];

  Widget _heading(IconData icon, String text) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      0,
      AppSpacing.md,
      AppSpacing.sm,
    ),
    sliver: SliverToBoxAdapter(
      child: _SectionTitle(
        icon: icon,
        color: Theme.of(context).colorScheme.primary,
        text: text,
      ),
    ),
  );

  List<Widget> _resultSlivers(BuildContext context) {
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
                TextButton(
                  onPressed: () => _search(_query),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final loaded = _results;
    if (loaded == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final results = _available(loaded);
    if (results.isEmpty) {
      if (_searching) return const [];
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Message(
            icon: Icons.search_off,
            title: "No results for '$_query'",
            text: 'Try another word, or check the spelling.',
          ),
        ),
      ];
    }

    final others = _available(_otherStalls);
    return [
      _heading(Icons.auto_awesome, 'Best Match'),
      ..._rows(results),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _loadMoreFooter(),
        ),
      ),
      if (others.isNotEmpty) ...[
        _heading(Icons.storefront, 'Other Vendors You Might Like'),
        ..._rows(others),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ],
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

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search for Surplus Food',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Find meals by item, vendor or category',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _searchBox(),
                  ],
                ),
              ),
            ),
            ...(_query.isEmpty
                ? _startSlivers(context)
                : _resultSlivers(context)),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  static const double size = 84;

  final String category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('category-$category'),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.primaryPale,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  categoryIcon(category),
                  size: 24,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentPill extends StatelessWidget {
  const _RecentPill({
    super.key,
    required this.term,
    required this.onTap,
    required this.onRemove,
  });

  final String term;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: AppColors.primaryPale,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 16, color: colors.primary),
              const SizedBox(width: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onRemove,
                icon: Icon(Icons.close, color: colors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
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
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
