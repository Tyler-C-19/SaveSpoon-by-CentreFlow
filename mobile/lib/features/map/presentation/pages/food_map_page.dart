import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/auto_refresh.dart';
import '../../../listings/data/listing_repository.dart';
import '../../../listings/domain/search_filters.dart';
import '../../../listings/presentation/widgets/active_filter_chips.dart';
import '../../../listings/presentation/widgets/filter_sheet.dart';
import '../../../listings/presentation/widgets/icon_scale.dart';
import '../../../seller_profile/domain/geo_point.dart';
import '../../../seller_profile/presentation/widgets/vendor_pane.dart';
import '../../domain/distance.dart';
import '../../domain/map_stall.dart';
import '../providers/user_location_provider.dart';
import '../widgets/location_note.dart';
import '../widgets/stall_marker.dart';

// fitNow is the first view, set without animating.
enum MapMove { fitNow, fitAll, showMe, zoomIn, zoomOut }

// What the map draws; kept apart from Google's widget so tests can stand in.
class StallMapView {
  const StallMapView({
    required this.stalls,
    required this.here,
    required this.onStallTap,
    required this.moves,
    this.padding = EdgeInsets.zero,
    this.onReady,
  });

  final List<MapStall> stalls;
  final GeoPoint? here;
  final ValueChanged<MapStall> onStallTap;
  // Each new value moves the camera once.
  final ValueListenable<(MapMove, int)?> moves;
  // Covered by the search card on top and the phone's bar at the bottom.
  final EdgeInsets padding;
  // Called once the first view has been drawn.
  final VoidCallback? onReady;
}

typedef StallMapBuilder = Widget Function(
  BuildContext context,
  StallMapView view,
);

Widget googleStallMap(BuildContext context, StallMapView view) =>
    GoogleStallMap(view: view);

// Opened from Search with its keyword and filters. Location is asked here,
// over Search, so the map slides in afterwards; the stalls start loading at
// the same time.
Future<void> openFoodMap(
  BuildContext context, {
  String query = '',
  SearchFilters filters = SearchFilters.none,
}) async {
  final keyword = query.trim();
  final shown = filters.copyWith(sort: null);
  final firstLoad = context.read<ListingRepository>().fetchMap(
    query: keyword,
    filters: shown,
  )..ignore();
  await context.read<UserLocationProvider?>()?.askPermission();
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          FoodMapPage(query: keyword, filters: shown, firstLoad: firstLoad),
    ),
  );
}

class FoodMapPage extends StatefulWidget {
  const FoodMapPage({
    super.key,
    this.query = '',
    this.filters = SearchFilters.none,
    this.mapBuilder = googleStallMap,
    this.firstLoad,
  });

  // The veil lifts by itself after this, even if the map hasn't said so.
  static const Duration revealAfter = Duration(seconds: 2);
  static const Duration revealFade = Duration(milliseconds: 300);

  static const String title = 'Discover Nearby Food';
  static const int maxKeywordLength = 50;
  static const String emptyMessage = 'No food on sale right now.';
  static const String noMatchMessage = 'No stalls match your search.';
  // The search card never takes more of the map than this; it scrolls inside.
  static const double maxCardShare = 0.4;

  final String query;
  final SearchFilters filters;
  final StallMapBuilder mapBuilder;
  // Stalls already loading when the map icon was tapped.
  final Future<List<MapStall>>? firstLoad;

  @override
  State<FoodMapPage> createState() => _FoodMapPageState();
}

class _FoodMapPageState extends State<FoodMapPage> with AutoRefresh {
  final ValueNotifier<(MapMove, int)?> _moves = ValueNotifier(null);
  final GlobalKey _cardKey = GlobalKey();
  late SearchFilters _filters = widget.filters;
  late String _query = widget.query;
  late final TextEditingController _keyword = TextEditingController(
    text: widget.query,
  );
  List<MapStall>? _stalls;
  String? _error;
  bool _serverDown = false;
  double _cardHeight = 0;
  int _requestId = 0;
  int _moveId = 0;
  bool _fitted = false;
  bool _firstFitDone = false;
  bool _locationDone = false;
  bool _revealed = false;
  bool _veilGone = false;
  Timer? _revealTimer;
  late Future<List<MapStall>>? _firstLoad = widget.firstLoad;

  bool get _searching => _query.isNotEmpty || _filters.hasFilters;

  @override
  void initState() {
    super.initState();
    _keyword.addListener(_onKeywordChanged);
    _revealTimer = Timer(FoodMapPage.revealAfter, _reveal);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  void _onKeywordChanged() {
    if (_keyword.text.trim().isEmpty && _query.isNotEmpty) _search('');
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _moves.dispose();
    _keyword.dispose();
    super.dispose();
  }

  @override
  Future<void> autoRefresh() async {
    context.read<UserLocationProvider?>()?.refreshIfAllowed();
    await _load(silent: true);
  }

  void _reveal() {
    _revealTimer?.cancel();
    if (mounted && !_revealed) setState(() => _revealed = true);
  }

  // Location was already asked when the map icon was tapped.
  Future<void> _locate() async {
    final location = context.read<UserLocationProvider?>();
    if (location != null) await location.locate();
    if (!mounted) return;
    _locationDone = true;
    _fitOnce();
  }

  void _fitOnce() {
    if (_fitted || !_locationDone || _stalls == null) return;
    _fitted = true;
    _move(_firstFitDone ? MapMove.fitAll : MapMove.fitNow);
    _firstFitDone = true;
  }

  void _move(MapMove move) => _moves.value = (move, ++_moveId);

  Future<void> _load({bool silent = false}) async {
    final request = ++_requestId;
    if (!silent) setState(() => _error = null);
    try {
      final repository = context.read<ListingRepository>();
      final early = _firstLoad;
      _firstLoad = null;
      final stalls =
          await (early ??
              repository.fetchMap(query: _query, filters: _filters));
      if (!mounted || request != _requestId) return;
      setState(() {
        _stalls = stalls;
        _error = null;
      });
      _fitOnce();
      // Stall details load in the background so a pin opens its pane filled.
      for (final stall in stalls) {
        repository.prefetchVendorInfo(stall.listing.id, all: true);
      }
    } on ApiException catch (e) {
      if (!mounted || request != _requestId) return;
      if (_stalls == null || !silent) {
        setState(() {
          _error = e.message;
          _serverDown = e.statusCode == null || e.statusCode! >= 500;
        });
      }
      _reveal();
    }
  }

  void _retry() {
    setState(() => _stalls = null);
    _load();
  }

  void _changeFilters(SearchFilters next) {
    setState(() {
      _filters = next;
      _fitted = false;
    });
    _load();
  }

  // A search here only changes the map, not the Search tab.
  void _search(String text) {
    final query = text.trim();
    if (query == _query) return;
    setState(() {
      _query = query;
      _fitted = false;
    });
    _load();
  }

  void _clearSearch() {
    _keyword.clear();
    _search('');
  }

  Future<void> _openFilters() async {
    FocusScope.of(context).unfocus();
    final next = await showFilterSheet(
      context,
      current: _filters,
      hasKeyword: _query.isNotEmpty,
      showSort: false,
    );
    if (next == null || !mounted) return;
    _changeFilters(next);
  }

  void _openStall(MapStall stall) => showVendorPane(
    context,
    listing: stall.listing,
    allItems: true,
    first: _searching ? stall.matches : const [],
  );

  // Keeps the map's camera clear of the search card.
  void _measureCard() {
    final height = _cardKey.currentContext?.size?.height;
    if (height != null && height != _cardHeight && mounted) {
      setState(() => _cardHeight = height);
    }
  }

  String get _heading {
    if (_query.isNotEmpty) return 'Results for "$_query"';
    if (_filters.hasFilters) return 'Best Matches';
    return 'Food Near You';
  }

  @override
  Widget build(BuildContext context) {
    final here = context.watch<UserLocationProvider?>()?.position;
    final stalls = _stalls;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureCard());

    return Scaffold(
      appBar: AppBar(title: const Text(FoodMapPage.title)),
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(
              child: widget.mapBuilder(
                context,
                StallMapView(
                  stalls: stalls ?? const [],
                  here: here,
                  onStallTap: _openStall,
                  moves: _moves,
                  onReady: _reveal,
                  padding: EdgeInsets.only(
                    top: _cardHeight + AppSpacing.sm,
                    bottom: bottomInset,
                  ),
                ),
              ),
            ),
            // Covers the map until its first view is drawn, then fades out
            // and is removed.
            if (!_veilGone)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _revealed,
                  child: AnimatedOpacity(
                    key: const ValueKey('map-veil'),
                    opacity: _revealed ? 0 : 1,
                    duration: FoodMapPage.revealFade,
                    curve: Curves.easeOut,
                    onEnd: () {
                      if (_revealed && mounted) {
                        setState(() => _veilGone = true);
                      }
                    },
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
              ),
            if (_revealed && stalls == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.md,
              right: AppSpacing.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    key: _cardKey,
                    constraints: BoxConstraints(
                      maxHeight:
                          constraints.maxHeight * FoodMapPage.maxCardShare,
                    ),
                    child: _SearchCard(
                      heading: _heading,
                      keyword: _keyword,
                      filters: _filters,
                      hasKeyword: _query.isNotEmpty,
                      onSearch: _search,
                      onClear: _clearSearch,
                      onFilters: _openFilters,
                      onChanged: _changeFilters,
                    ),
                  ),
                  if (_error != null)
                    MapBanner(
                      icon: _serverDown
                          ? Icons.power_off_outlined
                          : Icons.error_outline,
                      text: _error!,
                      action: 'Try Again',
                      onAction: _retry,
                    )
                  else if (stalls != null && stalls.isEmpty)
                    MapBanner(
                      icon: Icons.info_outline,
                      text: _searching
                          ? FoodMapPage.noMatchMessage
                          : FoodMapPage.emptyMessage,
                    ),
                ],
              ),
            ),
            // Google's own zoom buttons can't be moved, so these replace them,
            // stacked above My Location and clear of the Google logo.
            Positioned(
              right: AppSpacing.md,
              bottom: AppSpacing.xl + bottomInset,
              child: Column(
                key: const ValueKey('map-buttons'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    key: const ValueKey('zoom-in'),
                    heroTag: null,
                    tooltip: 'Zoom In',
                    onPressed: () => _move(MapMove.zoomIn),
                    child: Icon(Icons.add, size: 24 * iconScale(context)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FloatingActionButton.small(
                    key: const ValueKey('zoom-out'),
                    heroTag: null,
                    tooltip: 'Zoom Out',
                    onPressed: () => _move(MapMove.zoomOut),
                    child: Icon(Icons.remove, size: 24 * iconScale(context)),
                  ),
                  if (here != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    FloatingActionButton.small(
                      key: const ValueKey('my-location'),
                      heroTag: null,
                      tooltip: 'My Location',
                      onPressed: () => _move(MapMove.showMe),
                      child: Icon(
                        Icons.my_location,
                        size: 24 * iconScale(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The floating card at the top of the map: what is shown, the filter button,
// active filters and the location note.
class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.heading,
    required this.keyword,
    required this.filters,
    required this.hasKeyword,
    required this.onSearch,
    required this.onClear,
    required this.onFilters,
    required this.onChanged,
  });

  final String heading;
  final TextEditingController keyword;
  final SearchFilters filters;
  final bool hasKeyword;
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;
  final VoidCallback onFilters;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = filters.copyWith(sort: null).activeCount;
    return DecoratedBox(
      key: const ValueKey('map-card'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: AnimatedSize(
            duration: ActiveFilterChips.leaving,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.near_me_outlined,
                      size: 20 * iconScale(context),
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        heading,
                        key: const ValueKey('map-heading'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('map-filter-button'),
                      tooltip: 'Filters',
                      onPressed: onFilters,
                      icon: Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count'),
                        child: Icon(Icons.tune, size: 24 * iconScale(context)),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: keyword,
                    builder: (context, value, _) => TextField(
                      key: const ValueKey('map-search-box'),
                      controller: keyword,
                      textInputAction: TextInputAction.search,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          FoodMapPage.maxKeywordLength,
                        ),
                      ],
                      onSubmitted: onSearch,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search by food or vendor',
                        prefixIcon: Icon(
                          Icons.search,
                          size: 20 * iconScale(context),
                        ),
                        suffixIcon: value.text.isEmpty
                            ? null
                            : IconButton(
                                key: const ValueKey('map-search-clear'),
                                tooltip: 'Clear',
                                icon: Icon(
                                  Icons.close,
                                  size: 20 * iconScale(context),
                                ),
                                onPressed: onClear,
                              ),
                      ),
                    ),
                  ),
                ),
                if (filters.hasFilters)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ActiveFilterChips(
                      filters: filters,
                      hasKeyword: hasKeyword,
                      onChanged: onChanged,
                    ),
                  ),
                const LocationNote(
                  padding: EdgeInsets.only(
                    top: AppSpacing.xs,
                    right: AppSpacing.sm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// The look of the "Waking up the server" banner (SVS-39), for the map's own
// errors and empty results.
class MapBanner extends StatelessWidget {
  const MapBanner({
    super.key,
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      key: const ValueKey('map-banner'),
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primaryPale,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.primarySoft),
            boxShadow: AppShadows.card,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20 * iconScale(context),
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    text,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (action != null)
                  TextButton(onPressed: onAction, child: Text(action!)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// The distance to a stall, or null without the customer's location.
String? stallDistance(MapStall stall, GeoPoint? here) =>
    distanceBetween(here, stall.location);

class GoogleStallMap extends StatefulWidget {
  const GoogleStallMap({super.key, required this.view});

  // Further than this from every stall, the customer is left out of the
  // opening view so the map doesn't zoom out to the whole country.
  static const double nearbyMetres = 20000;
  // From this zoom in, pins show the stall name under them.
  static const double namesZoom = 17;

  final StallMapView view;

  @override
  State<GoogleStallMap> createState() => _GoogleStallMapState();
}

class _GoogleStallMapState extends State<GoogleStallMap> {
  static const double _startZoom = 16;
  static const double _closeZoom = 17;
  static const double _fitPadding = 64;

  GoogleMapController? _controller;
  StallMarkerIcons? _icons;
  Map<String, StallIcon> _drawn = {};
  bool _showNames = false;
  bool _waitingReady = false;
  (MapMove, int)? _pending;
  double _scale = 1;
  double _pixelRatio = 1;

  LatLng _latLng(GeoPoint point) => LatLng(point.lat, point.lng);

  @override
  void initState() {
    super.initState();
    widget.view.moves.addListener(_onMove);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = Theme.of(context).colorScheme;
    final scale = iconScale(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (_icons == null || scale != _scale || pixelRatio != _pixelRatio) {
      _icons = StallMarkerIcons(
        fill: colors.primary,
        onFill: colors.onPrimary,
        labelText: colors.onSurface,
        labelFill: colors.surface,
      );
      _scale = scale;
      _pixelRatio = pixelRatio;
      _drawn = {};
      _drawIcons();
    }
  }

  @override
  void didUpdateWidget(GoogleStallMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.moves != widget.view.moves) {
      oldWidget.view.moves.removeListener(_onMove);
      widget.view.moves.addListener(_onMove);
    }
    _drawIcons();
  }

  @override
  void dispose() {
    widget.view.moves.removeListener(_onMove);
    _controller?.dispose();
    super.dispose();
  }

  // One drawing per count, or per count and label when names show.
  String _iconKey(MapStall stall) => _showNames
      ? '${stall.count}|${stall.stallName}|'
            '${stallDistance(stall, widget.view.here) ?? ''}'
      : '${stall.count}';

  Future<void> _drawIcons() async {
    final icons = _icons!;
    final missing = [
      for (final stall in widget.view.stalls)
        if (!_drawn.containsKey(_iconKey(stall))) stall,
    ];
    for (final stall in missing) {
      final key = _iconKey(stall);
      final icon = await icons.icon(
        stall.count,
        name: _showNames ? stall.stallName : null,
        distance: _showNames ? stallDistance(stall, widget.view.here) : null,
        scale: _scale,
        pixelRatio: _pixelRatio,
      );
      if (!mounted || icons != _icons) return;
      setState(() => _drawn = {..._drawn, key: icon});
    }
  }

  String _pinId(MapStall stall) =>
      '${stall.stallName}-${stall.location.lat}-${stall.location.lng}';

  void _onCameraMove(CameraPosition position) {
    final showNames = position.zoom >= GoogleStallMap.namesZoom;
    if (showNames == _showNames) return;
    setState(() => _showNames = showNames);
    _drawIcons();
  }

  void _onMove() {
    final move = widget.view.moves.value;
    if (move == null) return;
    if (_controller == null) {
      _pending = move;
      return;
    }
    _apply(move.$1);
  }

  List<GeoPoint> _fitPoints() {
    final stalls = [for (final stall in widget.view.stalls) stall.location];
    final here = widget.view.here;
    final nearby =
        here != null &&
        stalls.any(
          (point) => metresBetween(here, point) <= GoogleStallMap.nearbyMetres,
        );
    return [...stalls, if (here != null && (nearby || stalls.isEmpty)) here];
  }

  Future<void> _apply(MapMove move) async {
    final controller = _controller;
    if (controller == null) return;
    final here = widget.view.here;
    if (move == MapMove.zoomIn || move == MapMove.zoomOut) {
      await controller.animateCamera(
        move == MapMove.zoomIn ? CameraUpdate.zoomIn() : CameraUpdate.zoomOut(),
      );
      return;
    }
    if (move == MapMove.showMe && here != null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(_latLng(here), _closeZoom),
      );
      return;
    }
    final now = move == MapMove.fitNow;
    final points = _fitPoints();
    if (points.isEmpty) {
      if (now) widget.view.onReady?.call();
      return;
    }
    final lats = points.map((point) => point.lat);
    final lngs = points.map((point) => point.lng);
    final update = points.length == 1
        ? CameraUpdate.newLatLngZoom(_latLng(points.first), _closeZoom)
        : CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
              northeast: LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
            ),
            _fitPadding,
          );
    if (now) {
      _waitingReady = true;
      await controller.moveCamera(update);
    } else {
      await controller.animateCamera(update);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _latLng(GeoPoint.utmSkudai),
        zoom: _startZoom,
      ),
      padding: widget.view.padding,
      onMapCreated: (controller) {
        _controller = controller;
        final pending = _pending;
        _pending = null;
        if (pending != null) _apply(pending.$1);
      },
      onCameraMove: _onCameraMove,
      onCameraIdle: () {
        if (!_waitingReady) return;
        _waitingReady = false;
        widget.view.onReady?.call();
      },
      markers: {
        for (final stall in widget.view.stalls)
          Marker(
            markerId: MarkerId(_pinId(stall)),
            position: _latLng(stall.location),
            icon:
                (_drawn[_iconKey(stall)] ?? _drawn['${stall.count}'])?.icon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
            anchor:
                (_drawn[_iconKey(stall)] ?? _drawn['${stall.count}'])?.anchor ??
                StallMarkerIcons.anchor,
            consumeTapEvents: true,
            onTap: () => widget.view.onStallTap(stall),
          ),
      },
      myLocationEnabled: widget.view.here != null,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}
