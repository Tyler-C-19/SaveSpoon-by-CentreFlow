import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../data/vendor_repository.dart';
import '../../domain/geo_point.dart';
import '../../domain/vendor_validators.dart';

class PlaceSearchField extends StatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.controller,
    required this.repository,
    required this.onPlaceChosen,
  });

  static const Duration typingPause = Duration(milliseconds: 400);
  static const int minLength = 3;

  final TextEditingController controller;
  final VendorRepository repository;
  final void Function(GeoPoint location, String placeId) onPlaceChosen;

  @override
  State<PlaceSearchField> createState() => PlaceSearchFieldState();
}

class PlaceSearchFieldState extends State<PlaceSearchField> {
  Timer? _timer;
  String _lastQuery = '';
  String _sessionToken = _newToken();
  int _latestRequest = 0;
  List<PlaceSuggestion> _suggestions = const [];
  String? _error;

  static String _newToken() {
    final random = Random.secure();
    return base64Url.encode(List.generate(24, (_) => random.nextInt(256)));
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void fill(String address) {
    _timer?.cancel();
    _latestRequest++;
    _lastQuery = address.trim();
    widget.controller.text = address;
    setState(() {
      _suggestions = const [];
      _error = null;
    });
  }

  void _onChanged() {
    final text = widget.controller.text.trim();
    if (text == _lastQuery) return;
    _lastQuery = text;
    _timer?.cancel();
    _latestRequest++;
    if (text.length < PlaceSearchField.minLength) {
      setState(() {
        _suggestions = const [];
        _error = null;
      });
      return;
    }
    _timer = Timer(PlaceSearchField.typingPause, () => _search(text));
  }

  Future<void> _search(String text) async {
    final request = ++_latestRequest;
    try {
      final found = await widget.repository.searchPlaces(text, _sessionToken);
      if (!mounted || request != _latestRequest) return;
      setState(() {
        _suggestions = found;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _latestRequest) return;
      setState(() {
        _suggestions = const [];
        _error = e.message;
      });
    }
  }

  Future<void> _choose(PlaceSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    final token = _sessionToken;
    _sessionToken = _newToken();
    fill(suggestion.text);
    final request = _latestRequest;
    try {
      final location = await widget.repository.placeLocation(
        suggestion.placeId,
        token,
      );
      if (mounted && request == _latestRequest) {
        widget.onPlaceChosen(location, suggestion.placeId);
      }
    } on ApiException catch (e) {
      if (mounted && request == _latestRequest) {
        setState(() => _error = e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Pickup address',
          icon: Icons.place_outlined,
          controller: widget.controller,
          validator: VendorValidators.address,
        ),
        if (_suggestions.isNotEmpty) ...[
          for (final suggestion in _suggestions)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(suggestion.text),
              contentPadding: EdgeInsets.zero,
              onTap: () => _choose(suggestion),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Google Maps', style: textTheme.labelSmall),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ErrorText(_error),
        ],
      ],
    );
  }
}
