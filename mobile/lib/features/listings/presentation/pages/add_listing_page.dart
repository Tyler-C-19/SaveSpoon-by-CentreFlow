import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing_validators.dart';
import '../../domain/pickup_times.dart';
import '../widgets/allergen_picker.dart';
import '../widgets/category_picker.dart';

typedef TimePicker = Future<TimeOfDay?> Function(
  BuildContext context,
  TimeOfDay initial,
);

Future<TimeOfDay?> _materialTimePicker(
  BuildContext context,
  TimeOfDay initial,
) => showTimePicker(context: context, initialTime: initial);

DateTime _systemNow() => DateTime.now();

class AddListingPage extends StatefulWidget {
  const AddListingPage({
    super.key,
    this.timePicker = _materialTimePicker,
    this.now = _systemNow,
  });

  final TimePicker timePicker;
  final DateTime Function() now;

  @override
  State<AddListingPage> createState() => _AddListingPageState();
}

class _AddListingPageState extends State<AddListingPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _originalPrice = TextEditingController();
  final _discountedPrice = TextEditingController();
  final _stock = TextEditingController();
  final _otherAllergens = TextEditingController();

  String? _category;
  bool? _isHalal;
  late TimeOfDay _start;
  late TimeOfDay _end;
  String? _timeError;
  final Set<String> _allergens = {};

  bool _submitted = false;
  bool _isSaving = false;
  bool _isSuggesting = false;
  bool _usedAi = false;
  bool _aiFoundNothing = false;
  bool _allergensConfirmed = false;
  String? _aiError;
  String? _error;

  @override
  void initState() {
    super.initState();
    final start = PickupTimes.defaultStart(widget.now());
    _start = TimeOfDay.fromDateTime(start);
    _end = TimeOfDay.fromDateTime(PickupTimes.defaultEnd(start));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _originalPrice.dispose();
    _discountedPrice.dispose();
    _stock.dispose();
    _otherAllergens.dispose();
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

  Future<void> _suggestAllergens() async {
    final invalid =
        ListingValidators.title(_title.text) ??
        ListingValidators.description(_description.text);
    if (invalid != null) {
      setState(() => _aiError = invalid);
      return;
    }

    setState(() {
      _aiError = null;
      _isSuggesting = true;
    });
    try {
      final suggested = await context
          .read<ListingRepository>()
          .suggestAllergens(
            title: _title.text.trim(),
            description: _description.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _allergens
          ..clear()
          ..addAll(suggested.allergens);
        _otherAllergens.text = suggested.otherAllergens.join(', ');
        _usedAi = true;
        _aiFoundNothing =
            suggested.allergens.isEmpty && suggested.otherAllergens.isEmpty;
        _allergensConfirmed = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _aiError = e.message);
    } finally {
      if (mounted) setState(() => _isSuggesting = false);
    }
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final formValid = _formKey.currentState!.validate();
    final complete =
        formValid &&
        _category != null &&
        _isHalal != null &&
        _pickupError == null &&
        (!_usedAi || _allergensConfirmed);
    setState(() {
      _submitted = true;
      _error = complete ? null : 'Check the highlighted fields.';
    });
    if (!complete) return;

    setState(() => _isSaving = true);
    final now = widget.now();
    try {
      final listing = await context.read<ListingRepository>().create(
        title: _title.text.trim(),
        description: _description.text.trim(),
        category: _category!,
        isHalal: _isHalal!,
        originalPrice: double.parse(_originalPrice.text.trim()),
        discountedPrice: double.parse(_discountedPrice.text.trim()),
        quantityAvailable: int.parse(_stock.text.trim()),
        pickupStart: _onDay(now, _start),
        pickupEnd: _onDay(now, _end),
        allergens: _allergens.toList(),
        otherAllergens: ListingValidators.splitOtherAllergens(
          _otherAllergens.text,
        ),
      );
      if (mounted) context.pop(listing);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _fieldError(String? message) {
    if (!_submitted || message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.md);
    const sideGap = SizedBox(width: AppSpacing.sm);

    return Scaffold(
      appBar: AppBar(title: const Text('Add a Listing')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  label: 'Item name',
                  icon: Icons.fastfood_outlined,
                  controller: _title,
                  validator: ListingValidators.title,
                ),
                gap,
                AppTextField(
                  label: 'Description (optional)',
                  icon: Icons.notes_outlined,
                  controller: _description,
                  maxLines: 3,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  validator: ListingValidators.description,
                ),
                _heading('Category'),
                CategoryPicker(
                  selected: _category,
                  onChanged: (value) => setState(() => _category = value),
                ),
                _fieldError(_category == null ? 'Choose a category.' : null),
                _heading('Is this food halal?'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Yes')),
                    ButtonSegment(value: false, label: Text('No')),
                  ],
                  selected: {?_isHalal},
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  onSelectionChanged: (values) => setState(
                    () => _isHalal = values.isEmpty ? null : values.first,
                  ),
                ),
                _fieldError(_isHalal == null ? 'Choose Yes or No.' : null),
                _heading('Price and stock'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'Original (RM)',
                        controller: _originalPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: ListingValidators.originalPrice,
                      ),
                    ),
                    sideGap,
                    Expanded(
                      child: AppTextField(
                        label: 'Discounted (RM)',
                        controller: _discountedPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) => ListingValidators.discountedPrice(
                          value,
                          _originalPrice.text,
                        ),
                      ),
                    ),
                  ],
                ),
                gap,
                AppTextField(
                  label: 'Stock',
                  icon: Icons.inventory_2_outlined,
                  controller: _stock,
                  keyboardType: TextInputType.number,
                  validator: ListingValidators.stock,
                ),
                _heading('Pickup time today'),
                Row(
                  children: [
                    Expanded(child: _timeField('Start', _start, isStart: true)),
                    sideGap,
                    Expanded(child: _timeField('End', _end, isStart: false)),
                  ],
                ),
                if (_timeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      _timeError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  )
                else
                  _fieldError(_pickupError),
                const SizedBox(height: AppSpacing.lg),
                AllergenPicker(
                  selected: _allergens,
                  otherAllergens: _otherAllergens,
                  onToggled: (allergen) => setState(() {
                    if (!_allergens.remove(allergen)) _allergens.add(allergen);
                  }),
                  onSuggest: _suggestAllergens,
                  isSuggesting: _isSuggesting,
                  usedAi: _usedAi,
                  foundNothing:
                      _aiFoundNothing &&
                      _allergens.isEmpty &&
                      _otherAllergens.text.trim().isEmpty,
                  confirmed: _allergensConfirmed,
                  onConfirmed: (value) =>
                      setState(() => _allergensConfirmed = value),
                ),
                if (_aiError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ErrorText(_aiError),
                ],
                _fieldError(
                  _usedAi && !_allergensConfirmed
                      ? 'Tick the box to confirm the allergens.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                ErrorText(_error),
                AppButton(
                  label: 'Save Listing',
                  isLoading: _isSaving,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
