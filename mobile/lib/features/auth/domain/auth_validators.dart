import 'dart:convert';

// Keep in sync with backend authValidators.js.
abstract final class AuthValidators {
  static const String passwordRule =
      'At least 8 characters, with a letter and a number.';

  static String? name(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text.length > 100) return 'Enter your full name.';
    return null;
  }

  static String? email(String? value) {
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return valid.hasMatch(value?.trim() ?? '')
        ? null
        : 'Enter a valid email address.';
  }

  static String? phone(String? value) {
    final valid = RegExp(r'^\+?[0-9][0-9\s-]{6,18}[0-9]$');
    return valid.hasMatch(value?.trim() ?? '')
        ? null
        : 'Enter a valid phone number.';
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.length < 8) return 'Password must be at least 8 characters.';
    if (utf8.encode(text).length > 72) {
      return 'Password must be 72 characters or fewer.';
    }
    if (!text.contains(RegExp('[A-Za-z]')) || !text.contains(RegExp('[0-9]'))) {
      return 'Password must include at least one letter and one number.';
    }
    return null;
  }

  static String? required(String? value, String message) =>
      (value == null || value.isEmpty) ? message : null;

  static String? Function(String?) confirms(String Function() original) =>
      (value) => value == original() ? null : 'Passwords do not match.';

  static String? code(String value) =>
      RegExp(r'^[0-9]{6}$').hasMatch(value) ? null : 'Enter the 6-digit code.';
}
