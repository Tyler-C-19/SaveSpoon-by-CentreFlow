import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../../profile/data/photo_picker.dart';
import '../../../profile/presentation/widgets/picture_framer.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';
import '../../domain/listing_validators.dart';
import '../../domain/pickup_times.dart';
import '../widgets/allergen_picker.dart';
import '../widgets/category_picker.dart';
import '../widgets/active_orders_note.dart';
import '../widgets/listing_photo_field.dart';
import '../widgets/stock_changed_dialog.dart';

typedef TimePicker = Future<TimeOfDay?> Function(
  BuildContext context,
  TimeOfDay initial,
);

Future<TimeOfDay?> _materialTimePicker(
  BuildContext context,
  TimeOfDay initial,
) => showTimePicker(context: context, initialTime: initial);

DateTime _systemNow() => DateTime.now();

typedef ListingOpener = Future<Listing?> Function(
  BuildContext context,
  Listing listing,
);

Future<Listing?> _openNothing(BuildContext context, Listing listing) async =>
    null;

class AddListingPage extends StatefulWidget {
  const AddListingPage({
    super.key,
    this.timePicker = _materialTimePicker,
    this.now = _systemNow,
    this.existing = const [],
    this.onOpenExisting = _openNothing,
    this.onRelistExisting = _openNothing,
    this.editing,
    this.onViewOrders,
    this.photoPicker,
    this.sizer = decodeImageSize,
  });

  final PhotoPicker? photoPicker;
  final ImageSizer sizer;

  // Edits this listing instead of adding a new one.
  final Listing? editing;
  // Opens the vendor's Orders tab from the locked pickup time note.
  final void Function(BuildContext context)? onViewOrders;
  final TimePicker timePicker;
  final DateTime Function() now;
  // The vendor's listings, checked for the same name before saving.
  final List<Listing> existing;
  // Open over this form; coming back returns to the form as it was.
  final ListingOpener onOpenExisting;
  // Returns the listing if it was relisted, which also closes this form.
  final ListingOpener onRelistExisting;

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
  ListingPhotoDraft _photo = ListingPhotoDraft.keep;

  bool _submitted = false;
  bool _isSaving = false;
  bool _isSuggesting = false;
  bool _usedAi = false;
  bool _aiFoundNothing = false;
  bool _allergensConfirmed = false;
  String? _aiError;
  String? _error;

  // Edit mode only.
  late int _expectedStock = widget.editing?.quantityAvailable ?? 0;
  int _activeOrders = 0;
  String _initial = '';

  bool get _isEditing => widget.editing != null;

  // The vendor's other listings, checked for the same name.
  late List<Listing> _names = [
    for (final listing in widget.existing)
      if (listing.id != widget.editing?.id) listing,
  ];

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing == null) {
      final start = PickupTimes.defaultStart(widget.now());
      _start = TimeOfDay.fromDateTime(start);
      _end = TimeOfDay.fromDateTime(PickupTimes.defaultEnd(start));
    } else {
      _fill(editing);
      _initial = _snapshot();
      for (final field in [
        _title,
        _description,
        _originalPrice,
        _discountedPrice,
        _stock,
        _otherAllergens,
      ]) {
        field.addListener(_edited);
      }
      _loadForEdit(editing.id);
    }
    // Rebuild as the name changes so a same-item note can show straight away.
    _title.addListener(_nameChanged);
  }

  void _fill(Listing listing) {
    _title.text = listing.title;
    _description.text = listing.description ?? '';
    _originalPrice.text = listing.originalPrice.toStringAsFixed(2);
    _discountedPrice.text = listing.discountedPrice.toStringAsFixed(2);
    _stock.text = '${listing.quantityAvailable}';
    _category = listing.category;
    _isHalal = listing.isHalal;
    _allergens.addAll(listing.allergens);
    _otherAllergens.text = listing.otherAllergens.join(', ');
    _start = TimeOfDay.fromDateTime(listing.pickupStart);
    _end = TimeOfDay.fromDateTime(listing.pickupEnd);
  }

  // Active orders lock the pickup time; the vendor's other names feed the
  // same-item check. The server checks both again on save.
  Future<void> _loadForEdit(String id) async {
    final repository = context.read<ListingRepository>();
    try {
      final own = await repository.fetchMineOne(id);
      if (mounted) setState(() => _activeOrders = own.activeOrderCount);
    } on ApiException {
      // Saving still reports a locked pickup time.
    }
    if (widget.existing.isNotEmpty) return;
    try {
      final mine = await repository.fetchMine();
      if (!mounted) return;
      _names = [
        for (final listing in mine)
          if (listing.id != id) listing,
      ];
      _nameChanged();
    } on ApiException {
      // The server still refuses a same name.
    }
  }

  void _edited() => setState(() {});

  // Everything the vendor can change, so Save Changes can tell if anything did.
  String _snapshot() => [
    _title.text.trim(),
    _description.text.trim(),
    _category,
    _isHalal,
    double.tryParse(_originalPrice.text.trim()) ?? _originalPrice.text,
    double.tryParse(_discountedPrice.text.trim()) ?? _discountedPrice.text,
    int.tryParse(_stock.text.trim()) ?? _stock.text,
    _minutes(_start),
    _minutes(_end),
    (_allergens.toList()..sort()).join(','),
    [
      for (final item in ListingValidators.splitOtherAllergens(
        _otherAllergens.text,
      ))
        item.toLowerCase(),
    ].join(','),
  ].join('\n');

  static int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  bool get _detailsChanged => _snapshot() != _initial;

  bool get _dirty => _detailsChanged || _photo.isChange;

  bool get _windowLocked => _isEditing && _activeOrders > 0;

  bool get _halalChanged => _isEditing && _isHalal != widget.editing!.isHalal;

  bool get _allergensChanged {
    final editing = widget.editing;
    if (editing == null) return false;
    final before = {
      ...editing.allergens,
      for (final item in editing.otherAllergens) item.toLowerCase(),
    };
    final now = {
      ..._allergens,
      for (final item in ListingValidators.splitOtherAllergens(
        _otherAllergens.text,
      ))
        item.toLowerCase(),
    };
    return before.length != now.length || !before.containsAll(now);
  }

  static String? _editStockError(String? value) {
    final amount = int.tryParse(value?.trim() ?? '');
    return amount == null || amount < 0 || amount > 999
        ? 'Enter a whole number from 0 to 999.'
        : null;
  }

  Listing? _shownSameName;

  void _nameChanged() {
    final match = _sameNameListing();
    if (match?.id != _shownSameName?.id) setState(() => _shownSameName = match);
  }

  // Puts the name last so the sentence reads right for any item name.
  String _sameItemLine(Listing existing) {
    final listed = existing.isAvailableAt(widget.now());
    return 'You already have a listing for ${existing.title}, '
        '${listed ? "and it's active" : "but it's unlisted"}.';
  }

  String _sameItemAction(Listing existing) =>
      existing.canRelistAt(widget.now()) ? 'Relist It' : 'View Listing';

  // A short note under Item name while it matches one of the vendor's items.
  Widget _sameNameNote(Listing existing) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('same-item-note'),
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.warningPale,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.onWarning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _sameItemLine(existing),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onWarning,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _openSameName(existing),
            child: Text(_sameItemAction(existing)),
          ),
        ],
      ),
    );
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
    // An untouched window keeps its own dates, as it may end after midnight.
    final editing = widget.editing;
    if (editing != null &&
        _start == TimeOfDay.fromDateTime(editing.pickupStart) &&
        _end == TimeOfDay.fromDateTime(editing.pickupEnd)) {
      return ListingValidators.pickup(
        editing.pickupStart,
        editing.pickupEnd,
        now,
      );
    }
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

  static String _nameKey(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Listing? _sameNameListing() {
    final key = _nameKey(_title.text);
    for (final listing in _names) {
      if (_nameKey(listing.title) == key) return listing;
    }
    return null;
  }

  // Opens the existing listing over the form. A finished relist closes the
  // form too; otherwise the vendor comes back to what they typed.
  Future<void> _openSameName(Listing existing) async {
    if (!existing.canRelistAt(widget.now())) {
      await widget.onOpenExisting(context, existing);
      return;
    }
    final relisted = await widget.onRelistExisting(context, existing);
    if (relisted != null && mounted && !_isEditing) context.pop(relisted);
  }

  // Same names aren't allowed, so the only ways on are the existing listing
  // (true) or Cancel (false), which leaves this form. Null: popup dismissed.
  Future<bool?> _askAboutSameName(Listing existing) async {
    final error = Theme.of(context).colorScheme.error;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Same Item Found'),
        // The button carries the next step, so the text is just the fact.
        content: Text(_sameItemLine(existing)),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: error,
                    side: BorderSide(color: error),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(_sameItemAction(existing)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return open;
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

    final sameName = _sameNameListing();
    if (sameName != null) {
      setState(() => _error = null);
      final open = await _askAboutSameName(sameName);
      if (!mounted || open == null) return;
      if (open) {
        await _openSameName(sameName);
      } else if (!_isEditing) {
        // Cancel goes back to where the vendor came from; an edit keeps the form.
        context.pop();
      }
      return;
    }

    if (_isEditing) return _saveEdit();

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
      final withPhoto = await _savePhotoAfter(listing);
      if (mounted) context.pop(withPhoto);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<Listing> _applyPhoto(Listing listing) {
    final repository = context.read<ListingRepository>();
    final fresh = _photo.fresh;
    if (fresh != null) {
      return repository.setPhoto(
        listing.id,
        bytes: fresh.bytes,
        filename: fresh.filename,
        crop: _photo.crop!,
      );
    }
    if (_photo.removed) return repository.removePhoto(listing.id);
    return repository.reframePhoto(listing.id, _photo.crop!);
  }

  // Once the listing itself is saved; a failed photo leaves the listing saved.
  Future<Listing> _savePhotoAfter(Listing listing) async {
    if (!_photo.isChange) return listing;
    try {
      return await _applyPhoto(listing);
    } on ApiException catch (e) {
      _photoNotSaved(
        _byServer(e)
            ? "${listing.title} saved, but our server couldn't upload the "
                  'photo. Please re-add it from Edit Listing later.'
            : "${listing.title} saved, but the photo wasn't. ${e.message}",
      );
      return listing;
    }
  }

  // Server or connection trouble, as opposed to a refused file or the daily limit.
  static bool _byServer(ApiException e) =>
      e.statusCode == null || e.statusCode! >= 500;

  // Shown over the page the form returns to.
  void _photoNotSaved(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('photo-not-saved'),
          duration: const Duration(seconds: 6),
          content: Text(text),
        ),
      );
  }

  // Only the photo changed, so the listing details aren't sent again.
  Future<void> _savePhotoOnly() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final listing = await _applyPhoto(widget.editing!);
      if (mounted) context.pop(listing);
    } on ApiException catch (e) {
      // Nothing else changed, so the form closes with nothing saved but this note.
      _photoNotSaved(
        _byServer(e)
            ? "Our server couldn't upload the photo. Please try again later "
                  'from Edit Listing.'
            : "The photo wasn't saved. ${e.message}",
      );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveEdit() async {
    if (!_detailsChanged) return _savePhotoOnly();
    final editing = widget.editing!;
    final now = widget.now();
    // An untouched window is sent exactly as it was, so it doesn't count as moved.
    final sameWindow =
        _start == TimeOfDay.fromDateTime(editing.pickupStart) &&
        _end == TimeOfDay.fromDateTime(editing.pickupEnd);
    final stock = int.parse(_stock.text.trim());
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final listing = await context.read<ListingRepository>().update(
        id: editing.id,
        title: _title.text.trim(),
        description: _description.text.trim(),
        category: _category!,
        isHalal: _isHalal!,
        originalPrice: double.parse(_originalPrice.text.trim()),
        discountedPrice: double.parse(_discountedPrice.text.trim()),
        quantityAvailable: stock,
        expectedQuantity: _expectedStock,
        pickupStart: sameWindow ? editing.pickupStart : _onDay(now, _start),
        pickupEnd: sameWindow ? editing.pickupEnd : _onDay(now, _end),
        allergens: _allergens.toList(),
        otherAllergens: ListingValidators.splitOtherAllergens(
          _otherAllergens.text,
        ),
      );
      final withPhoto = await _savePhotoAfter(listing);
      if (mounted) context.pop(withPhoto);
    } on StockChangedException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final current = e.current.quantityAvailable;
      final setAnyway = await askAboutStockChange(
        context,
        message: e.message,
        current: current,
        wanted: stock,
      );
      if (!mounted) return;
      _expectedStock = current;
      if (setAnyway != true) _stock.text = '$current';
      await _saveEdit();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        if (e.code == 'PICKUP_LOCKED') {
          _activeOrders = _activeOrders > 0 ? _activeOrders : 1;
          _start = TimeOfDay.fromDateTime(editing.pickupStart);
          _end = TimeOfDay.fromDateTime(editing.pickupEnd);
        }
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // An amber note for changes that customers who already ordered are told about.
  Widget _orderedNote() => Padding(
    key: const ValueKey('ordered-note'),
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16, color: AppColors.onWarning),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Customers who ordered will be notified about this change.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.onWarning),
          ),
        ),
      ],
    ),
  );

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

  // Leaving drops unsaved edits, so ask first.
  Future<bool> _mayLeave() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text("Your changes to this listing won't be saved."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave == true && mounted;
  }

  Future<void> _viewOrders() async {
    if (await _mayLeave() && mounted) {
      widget.onViewOrders!(context);
    }
  }

  Future<void> _back() async {
    if (await _mayLeave() && mounted) Navigator.of(context).pop();
  }

  Widget _timeField(String label, TimeOfDay time, {required bool isStart}) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: _windowLocked ? null : () => _chooseTime(isStart: isStart),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(_windowLocked ? Icons.lock_outline : Icons.schedule),
          enabled: !_windowLocked,
        ),
        child: Text(
          time.format(context),
          style: _windowLocked
              ? TextStyle(color: Theme.of(context).disabledColor)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.md);
    const sideGap = SizedBox(width: AppSpacing.sm);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Listing' : 'Add a Listing'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Back (app bar or phone) asks first while edits are unsaved.
                PopScope<Object?>(
                  canPop: !_isEditing || !_dirty,
                  onPopInvokedWithResult: (didPop, result) {
                    if (!didPop) _back();
                  },
                  child: const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    'Photo (optional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ListingPhotoField(
                  draft: _photo,
                  onChanged: (draft) => setState(() => _photo = draft),
                  saved: widget.editing,
                  category: _category,
                  enabled: !_isSaving,
                  photoPicker: widget.photoPicker,
                  sizer: widget.sizer,
                ),
                gap,
                AppTextField(
                  label: 'Item name',
                  icon: Icons.fastfood_outlined,
                  controller: _title,
                  validator: ListingValidators.title,
                ),
                if (_shownSameName case final existing?)
                  _sameNameNote(existing),
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
                if (_activeOrders > 0 && _halalChanged) _orderedNote(),
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
                  validator: _isEditing
                      ? _editStockError
                      : ListingValidators.stock,
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
                if (_windowLocked)
                  ActiveOrdersNote(
                    key: const ValueKey('pickup-locked'),
                    count: _activeOrders,
                    onViewOrders: widget.onViewOrders == null
                        ? null
                        : _viewOrders,
                  ),
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
                if (_activeOrders > 0 && _allergensChanged) _orderedNote(),
                const SizedBox(height: AppSpacing.lg),
                ErrorText(_error),
                AppButton(
                  label: _isEditing ? 'Save Changes' : 'Save Listing',
                  isLoading: _isSaving,
                  onPressed: _isEditing && !_dirty ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
