// Keep in sync with backend vendorValidators.js.
abstract final class VendorValidators {
  static String? businessName(String? value) {
    final length = value?.trim().length ?? 0;
    return length < 2 || length > 80
        ? 'Business name must be 2 to 80 characters.'
        : null;
  }

  static String? address(String? value) {
    final length = value?.trim().length ?? 0;
    return length == 0 || length > 200
        ? 'Enter a pickup address of up to 200 characters.'
        : null;
  }

  static String? description(String? value) =>
      (value?.trim().length ?? 0) > 500
      ? 'Description must be 500 characters or fewer.'
      : null;
}
