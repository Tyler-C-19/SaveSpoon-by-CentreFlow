import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../../auth/domain/auth_validators.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/location_service.dart';
import '../../data/vendor_repository.dart';
import '../../domain/geo_point.dart';
import '../../domain/vendor_profile.dart';
import '../../domain/vendor_validators.dart';
import '../widgets/pickup_map.dart';
import '../widgets/place_search_field.dart';

class VendorSetupPage extends StatefulWidget {
  const VendorSetupPage({
    super.key,
    this.mapBuilder = googlePickupMap,
    this.locationService,
    this.initial,
    this.confirmLocationChange,
  });

  final PickupMapBuilder mapBuilder;
  final LocationService? locationService;

  // Set when editing an existing profile.
  final VendorProfile? initial;

  // Asked before a changed pin or address is saved. Returns false to cancel.
  final Future<bool> Function(BuildContext context)? confirmLocationChange;

  @override
  State<VendorSetupPage> createState() => _VendorSetupPageState();
}

class _VendorSetupPageState extends State<VendorSetupPage> {
  static const double _mapHeight = 280;

  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  late final TextEditingController _phone;
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _addressField = GlobalKey<PlaceSearchFieldState>();
  late final LocationService _location =
      widget.locationService ?? DeviceLocationService();

  GeoPoint _mapTarget = GeoPoint.utmSkudai;
  GeoPoint? _pin;
  String? _placeId;
  bool _isLoading = false;
  bool _isLocating = false;
  String? _locationError;
  String? _error;
  int _addressRequest = 0;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _phone = TextEditingController(
      text: initial?.phone ?? context.read<AuthProvider>().user?.phone ?? '',
    );
    if (initial != null) {
      _businessName.text = initial.businessName;
      _description.text = initial.description;
      _address.text = initial.address;
      _mapTarget = initial.pin;
      _pin = initial.pin;
      _placeId = initial.placeId;
      for (final field in [_businessName, _phone, _description, _address]) {
        field.addListener(_onEdited);
      }
    }
  }

  void _onEdited() => setState(() {});

  // Save Changes stays off until something differs from the saved profile.
  bool get _hasChanges {
    final initial = widget.initial;
    if (initial == null) return true;
    return _businessName.text.trim() != initial.businessName ||
        _phone.text.trim() != initial.phone ||
        _description.text.trim() != initial.description ||
        _address.text.trim() != initial.address ||
        _pin != initial.pin ||
        _placeId != initial.placeId;
  }

  @override
  void dispose() {
    _businessName.dispose();
    _phone.dispose();
    _description.dispose();
    _address.dispose();
    super.dispose();
  }

  static const String _noAddressMessage =
      "Couldn't find the address here. Type it in the box above.";

  Future<void> _onMapTap(GeoPoint point) async {
    final request = ++_addressRequest;
    setState(() {
      _pin = point;
      _placeId = null;
      _locationError = null;
    });
    final address = await _location.addressAt(point);
    if (!mounted || request != _addressRequest) return;
    if (address != null) {
      _addressField.currentState?.fill(address);
    } else {
      setState(() => _locationError = _noAddressMessage);
    }
  }

  Future<void> _useCurrentLocation() async {
    _addressRequest++;
    setState(() {
      _isLocating = true;
      _locationError = null;
    });
    final found = await _location.currentLocation();
    final address = found == null ? null : await _location.addressAt(found);
    if (!mounted) return;
    if (address != null) _addressField.currentState?.fill(address);
    setState(() {
      _isLocating = false;
      if (found == null) {
        _locationError =
            "Couldn't get your location. Search or move the map instead.";
      } else {
        _mapTarget = found;
        _pin = found;
        _placeId = null;
        if (address == null) _locationError = _noAddressMessage;
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final formValid = _formKey.currentState!.validate();
    if (_pin == null) {
      setState(() => _error = 'Set your pickup location to continue.');
    }
    if (!formValid || _pin == null) return;
    if (_isEditing) return _saveChanges();

    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    try {
      await context.read<VendorRepository>().createProfile(
        businessName: _businessName.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        description: _description.text.trim(),
        pin: _pin!,
        placeId: _placeId,
      );
      await auth.markVendorProfileSaved();
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        await auth.markVendorProfileSaved();
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    final initial = widget.initial!;
    final locationChanged =
        _pin != initial.pin || _address.text.trim() != initial.address.trim();
    final confirm = widget.confirmLocationChange;
    if (locationChanged && confirm != null && !await confirm(context)) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    final navigator = Navigator.of(context);
    try {
      final moved = await context.read<VendorRepository>().updateProfile(
        businessName: _businessName.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        description: _description.text.trim(),
        pin: _pin!,
        placeId: _placeId,
      );
      navigator.pop(
        !locationChanged
            ? 'Vendor details updated.'
            : moved == 0
            ? 'Pickup location updated.'
            : 'Pickup location updated on $moved '
                  'listing${moved == 1 ? '' : 's'}.',
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const gap = SizedBox(height: AppSpacing.md);

    return Scaffold(
      appBar: _isEditing ? AppBar() : null,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                _isEditing ? 'Vendor Details' : 'Set up your business',
                style: _isEditing
                    ? textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      )
                    : textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Customers will see these details when ordering.'),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: _isEditing ? 'Vendor name' : 'Business name',
                icon: Icons.storefront_outlined,
                controller: _businessName,
                validator: _isEditing
                    ? (value) => VendorValidators.businessName(value) == null
                          ? null
                          : 'Vendor name must be 2 to 80 characters.'
                    : VendorValidators.businessName,
              ),
              gap,
              AppTextField(
                label: 'Contact number',
                icon: Icons.phone_outlined,
                controller: _phone,
                keyboardType: TextInputType.phone,
                validator: AuthValidators.phone,
              ),
              gap,
              AppTextField(
                label: 'Description (optional)',
                icon: Icons.notes_outlined,
                controller: _description,
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                validator: VendorValidators.description,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Pickup location', style: textTheme.titleMedium),
              gap,
              PlaceSearchField(
                key: _addressField,
                controller: _address,
                repository: context.read<VendorRepository>(),
                onPlaceChosen: (location, placeId) => setState(() {
                  _mapTarget = location;
                  _pin = location;
                  _placeId = placeId;
                }),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _isLocating ? null : _useCurrentLocation,
                icon: _isLocating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  _isLocating
                      ? 'Finding your location…'
                      : 'Use my current location',
                ),
              ),
              if (_locationError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ErrorText(_locationError),
              ],
              gap,
              Text(
                _pin == null
                    ? 'Type a pickup address or tap the map to set your pickup location.'
                    : 'Pin placed. Tap the map to move it.',
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: SizedBox(
                  height: _mapHeight,
                  child: widget.mapBuilder(
                    context,
                    _mapTarget,
                    _pin,
                    _onMapTap,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ErrorText(_error),
              AppButton(
                label: _isEditing ? 'Save Changes' : 'Save and continue',
                isLoading: _isLoading,
                onPressed: _hasChanges ? _submit : null,
              ),
              if (!_isEditing) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: context.read<AuthProvider>().logout,
                  child: const Text('Log out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
