import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/auto_refresh.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';
import '../widgets/category_picker.dart';
import '../widgets/listing_card.dart';
import '../widgets/stock_editor.dart';

DateTime _systemNow() => DateTime.now();

class VendorListingPage extends StatefulWidget {
  const VendorListingPage({
    super.key,
    required this.listingId,
    required this.onRelist,
    this.initial,
    this.now = _systemNow,
  });

  final String listingId;
  final Listing? initial;
  // Opens the Relist Item step; returns the listing once it is back on sale.
  final Future<Listing?> Function(BuildContext context, Listing listing)
  onRelist;
  final DateTime Function() now;

  @override
  State<VendorListingPage> createState() => _VendorListingPageState();
}

class _VendorListingPageState extends State<VendorListingPage>
    with AutoRefresh {
  late Listing? _listing = widget.initial;
  late int _draft = widget.initial?.quantityAvailable ?? 0;
  int? _pastSold;
  String? _error;
  bool _savingStock = false;
  bool _switching = false;

  ListingRepository get _repository => context.read<ListingRepository>();

  bool get _dirty {
    final listing = _listing;
    return listing != null && _draft != listing.quantityAvailable;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Future<void> autoRefresh() => _load();

  Future<void> _load() async {
    try {
      final own = await _repository.fetchMineOne(widget.listingId);
      if (!mounted) return;
      _pastSold = own.pastSold;
      _show(own.listing);
    } on ApiException catch (e) {
      if (mounted && _listing == null) setState(() => _error = e.message);
    }
  }

  // Shows the latest listing, keeping a stock change the vendor hasn't saved.
  void _show(Listing listing) {
    setState(() {
      if (!_dirty) _draft = listing.quantityAvailable;
      _listing = listing;
      _error = null;
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveStock({int? expected}) async {
    final listing = _listing!;
    setState(() => _savingStock = true);
    try {
      final saved = await _repository.updateStock(
        id: listing.id,
        quantity: _draft,
        expectedQuantity: expected ?? listing.quantityAvailable,
      );
      if (!mounted) return;
      setState(() {
        _listing = saved;
        _draft = saved.quantityAvailable;
      });
      _message('Stock updated to ${saved.quantityAvailable}.');
    } on StockChangedException catch (e) {
      if (!mounted) return;
      setState(() {
        _listing = e.current;
        _savingStock = false;
      });
      await _confirmStock(e);
    } on ApiException catch (e) {
      if (!mounted) return;
      _message(e.message);
      await _load();
    } finally {
      if (mounted) setState(() => _savingStock = false);
    }
  }

  Future<void> _confirmStock(StockChangedException e) async {
    final current = e.current.quantityAvailable;
    final wanted = _draft;
    final reason = e.message.endsWith('.')
        ? e.message.substring(0, e.message.length - 1)
        : e.message;
    final setAnyway = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stock Changed'),
        content: Text('$reason, Set it to $wanted anyway?'),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Keep $current'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Set to $wanted'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (setAnyway == true) {
      await _saveStock(expected: current);
    } else {
      setState(() => _draft = current);
    }
  }

  Future<void> _setShown(bool shown) async {
    setState(() => _switching = true);
    try {
      final saved = await _repository.setPaused(_listing!.id, paused: !shown);
      if (!mounted) return;
      _show(saved);
      _message(
        shown ? 'Customers can see this listing again.' : 'Listing turned off.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _message(e.message);
      await _load();
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _relist() async {
    final relisted = await widget.onRelist(context, _listing!);
    if (relisted == null || !mounted) return;
    _message('${relisted.title} is back on sale.');
    await _load();
  }

  Widget _figure(
    String label,
    int value, {
    required String key,
    bool alignStart = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: alignStart
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        Text(
          '$value',
          key: ValueKey(key),
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    return Scaffold(
      appBar: AppBar(title: Text(listing?.title ?? 'Listing')),
      body: listing != null
          ? RefreshIndicator(onRefresh: _load, child: _details(listing))
          : _error == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _load();
                      },
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }

  Widget _note(String text, {IconData icon = Icons.info_outline}) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }

  Widget _details(Listing listing) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = widget.now();
    final canChange = listing.canChangeAt(now);
    final ended = listing.canRelistAt(now);
    final unlisted = listing.unlistedLabelAt(now);
    final endTime = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(listing.pickupEnd));
    final description = listing.description;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        ClipRRect(
          key: const ValueKey('listing-image'),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: SizedBox(
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: unlisted == null
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primaryPale, AppColors.primarySoft],
                      )
                    : null,
                color: unlisted == null ? null : AppColors.unlisted,
              ),
              child: Center(
                child: Icon(
                  categoryIcon(listing.category),
                  size: 80,
                  color: unlisted == null
                      ? colors.primary
                      : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                listing.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: unlisted == null
                    ? AppColors.primaryPale
                    : AppColors.warningPale,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                unlisted ?? 'Listed',
                key: const ValueKey('listing-status'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: unlisted == null
                      ? colors.primary
                      : AppColors.onWarning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              moneyLabel(listing.discountedPrice),
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              moneyLabel(listing.originalPrice),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ],
        ),
        _section('Stock', [
          Row(
            children: [
              if (ended)
                _figure(
                  'Stock Left',
                  listing.quantityAvailable,
                  key: 'stock-left',
                  alignStart: true,
                )
              else
                StockEditor(
                  value: _draft,
                  onChanged: canChange && !_savingStock
                      ? (value) => setState(() => _draft = value)
                      : null,
                ),
              const Spacer(),
              _figure('Sold Today', listing.soldCount, key: 'sold-today'),
              const SizedBox(width: AppSpacing.md),
              _figure(
                'Total Sold',
                (_pastSold ?? 0) + listing.soldCount,
                key: 'total-sold',
              ),
            ],
          ),
          if (ended)
            _note(
              'Pickup window has ended for today. Relist to put it back on sale.',
              icon: Icons.event_busy_outlined,
            )
          else if (listing.quantityAvailable <= 0)
            _note(
              'Adding stock puts this item back on sale until pickup ends at '
              '$endTime.',
            ),
          const SizedBox(height: AppSpacing.md),
          if (ended)
            FilledButton.icon(
              key: const ValueKey('relist-button'),
              onPressed: _relist,
              icon: const Icon(Icons.replay),
              label: const Text('Relist'),
            )
          else
            AppButton(
              label: 'Save Changes',
              isLoading: _savingStock,
              onPressed: canChange && _dirty ? _saveStock : null,
            ),
        ]),
        _section('Availability', [
          SwitchListTile(
            key: const ValueKey('shown-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Show to Customers'),
            subtitle: Text(
              listing.isPaused
                  ? 'Turned off. Customers cannot see or order this.'
                  : 'Customers can find and order this while it has stock.',
            ),
            value: !listing.isPaused,
            onChanged: canChange && !_switching ? _setShown : null,
          ),
          if (ended)
            _note(
              'Pickup window has ended for today.',
              icon: Icons.event_busy_outlined,
            )
          else if (listing.isPaused)
            _note(
              'Orders already placed still need to be prepared and collected.',
            ),
        ]),
        _section('Details', [
          _InfoRow(
            icon: Icons.schedule,
            label: 'Pickup time',
            value: pickupLabel(context, listing),
          ),
          _InfoRow(
            icon: categoryIcon(listing.category),
            label: 'Category',
            value: listing.category ?? 'Other',
          ),
          _InfoRow(
            icon: Icons.verified_outlined,
            label: 'Halal',
            value: listing.isHalal == true ? 'Yes' : 'No',
          ),
          _InfoRow(
            icon: Icons.info_outline,
            label: 'Allergens',
            value: listing.allergenSummary,
          ),
          if (description != null && description.isNotEmpty)
            _InfoRow(
              icon: Icons.notes_outlined,
              label: 'Description',
              value: description,
            ),
        ]),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
