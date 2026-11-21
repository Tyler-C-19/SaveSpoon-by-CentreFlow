import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';
import '../../domain/listing_validators.dart';
import '../../domain/pickup_times.dart';
import '../widgets/food_thumbnail.dart';
import '../widgets/listing_image.dart';
import 'add_listing_page.dart' show TimePicker;

Future<TimeOfDay?> _materialTimePicker(
  BuildContext context,
  TimeOfDay initial,
) => showTimePicker(context: context, initialTime: initial);

DateTime _systemNow() => DateTime.now();

// Puts an ended listing back on sale with new stock and pickup times.
class RelistPage extends StatefulWidget {
  const RelistPage({
    super.key,
    required this.listing,
    this.timePicker = _materialTimePicker,
    this.now = _systemNow,
  });

  final Listing listing;
  final TimePicker timePicker;
  final DateTime Function() now;

  @override
  State<RelistPage> createState() => _RelistPageState();
}

class _RelistPageState extends State<RelistPage> {
  final _formKey = GlobalKey<FormState>();
  final _stock = TextEditingController();
  late TimeOfDay _start;
  late TimeOfDay _end;
  String? _timeError;
  String? _error;
  bool _submitted = false;
  bool _isSaving = false;
  bool _shown = true;

  @override
  void initState() {
    super.initState();
    final start = PickupTimes.defaultStart(widget.now());
    _start = TimeOfDay.fromDateTime(start);
    _end = TimeOfDay.fromDateTime(PickupTimes.defaultEnd(start));
  }

  @override
  void dispose() {
    _stock.dispose();
    super.dispose();
  }

  DateTime _onDay(DateTime day, TimeOfDay time) =>
      DateTime(day.year, day.month, day.day, time.hour, time.minute);

  String? get _pickupError {
    final now = widget.now();
    return ListingValidators.pickup(
      _onDay(now, _start),
      _onDay(now, _end),
      now,
    );
  }

  Future<void> _chooseTime({required bool isStart}) async {
    final picked = await widget.timePicker(context, isStart ? _start : _end);
    if (picked == null || !mounted) return;

    final now = widget.now();
    final chosen = _onDay(now, picked);
    setState(() {
      if (isStart) {
        _timeError = PickupTimes.startError(chosen, now);
        if (_timeError != null) return;
        _start = picked;
        if (!_onDay(now, _end).isAfter(chosen)) {
          _end = TimeOfDay.fromDateTime(PickupTimes.defaultEnd(chosen));
        }
        _timeError = _pickupError;
      } else {
        _timeError = PickupTimes.endError(chosen, _onDay(now, _start), now);
        if (_timeError == null) _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final complete = _formKey.currentState!.validate() && _pickupError == null;
    setState(() {
      _submitted = true;
      _error = complete ? null : 'Check the highlighted fields.';
    });
    if (!complete) return;

    setState(() => _isSaving = true);
    final now = widget.now();
    try {
      final relisted = await context.read<ListingRepository>().relist(
        id: widget.listing.id,
        quantityAvailable: int.parse(_stock.text.trim()),
        pickupStart: _onDay(now, _start),
        pickupEnd: _onDay(now, _end),
        paused: !_shown,
      );
      if (mounted) context.pop(relisted.listing);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _timeField(String label, TimeOfDay time, {required bool isStart}) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => _chooseTime(isStart: isStart),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule),
        ),
        child: Text(time.format(context)),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final listing = widget.listing;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textMuted,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      // The photo runs the full height of the text beside it.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              key: const ValueKey('relist-photo'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: PhotoColumn(
                width: 96,
                child: ListingImage(
                  url: listing.cardImageUrl,
                  category: listing.category,
                  iconSize: 40,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Wraps to a second line rather than overflow.
                  Wrap(
                    spacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        moneyLabel(listing.discountedPrice),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        moneyLabel(listing.originalPrice),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${listing.category ?? 'Other'} · '
                    '${listing.isHalal == true ? 'Halal' : 'Non-Halal'}',
                    style: muted,
                  ),
                  Text('Allergens: ${listing.allergenSummary}', style: muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Relist Item')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summary(context),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Stock',
                  icon: Icons.inventory_2_outlined,
                  controller: _stock,
                  keyboardType: TextInputType.number,
                  validator: ListingValidators.stock,
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.lg,
                    bottom: AppSpacing.sm,
                  ),
                  child: Text(
                    'Pickup time today',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Row(
                  children: [
                    Expanded(child: _timeField('Start', _start, isStart: true)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _timeField('End', _end, isStart: false)),
                  ],
                ),
                if (_timeError != null || (_submitted && _pickupError != null))
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      _timeError ?? _pickupError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.lg,
                    bottom: AppSpacing.xs,
                  ),
                  child: Text(
                    'Availability',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('relist-shown-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show to Customers'),
                  subtitle: Text(
                    _shown
                        ? 'Customers can find and order this once relisted.'
                        : 'Customers won\'t see this yet. Turn it on from the '
                              'listing when you\'re ready.',
                  ),
                  value: _shown,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _shown = value),
                ),
                const SizedBox(height: AppSpacing.md),
                ErrorText(_error),
                AppButton(
                  label: 'Relist Item',
                  isLoading: _isSaving,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Other details can be edited while the listing is live.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
