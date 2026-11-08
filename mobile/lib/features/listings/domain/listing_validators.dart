// Keep in sync with backend listingValidators.js.
abstract final class ListingValidators {
  static final RegExp _money = RegExp(r'^\d+(\.\d{1,2})?$');
  static final RegExp _wholeNumber = RegExp(r'^\d+$');
  static final RegExp _otherAllergen = RegExp(
    r"^\p{L}[\p{L} '\-]{1,39}$",
    unicode: true,
  );

  static String? title(String? value) {
    final length = value?.trim().length ?? 0;
    return length < 2 || length > 80
        ? 'Item name must be 2 to 80 characters.'
        : null;
  }

  static String? description(String? value) => (value?.trim().length ?? 0) > 500
      ? 'Description must be 500 characters or fewer.'
      : null;

  static double? _price(String? value) {
    final text = value?.trim() ?? '';
    if (!_money.hasMatch(text)) return null;
    final price = double.parse(text);
    return price > 0 ? price : null;
  }

  static String? originalPrice(String? value) => _price(value) == null
      ? 'Enter a price above 0, with up to 2 decimal places.'
      : null;

  static String? discountedPrice(String? value, String? original) {
    final discounted = _price(value);
    if (discounted == null) {
      return 'Enter a price above 0, with up to 2 decimal places.';
    }
    final full = _price(original);
    return full != null && discounted >= full
        ? 'Must be less than the original price.'
        : null;
  }

  static String? stock(String? value) {
    final text = value?.trim() ?? '';
    final amount = _wholeNumber.hasMatch(text) ? int.tryParse(text) : null;
    return amount == null || amount < 1 || amount > 999
        ? 'Enter a whole number from 1 to 999.'
        : null;
  }

  static List<String> splitOtherAllergens(String? value) => [
    for (final item in (value ?? '').split(','))
      if (item.trim().isNotEmpty) item.trim(),
  ];

  static String? otherAllergens(String? value) {
    final items = splitOtherAllergens(value);
    return items.length > 5 || !items.every(_otherAllergen.hasMatch)
        ? 'Enter up to 5 names of 2 to 40 letters, separated by commas.'
        : null;
  }

  static String? pickup(DateTime? start, DateTime? end, DateTime now) {
    if (start == null || end == null) {
      return 'Choose a pickup start and end time.';
    }
    if (!end.isAfter(start)) return 'Pickup must end after it starts.';
    if (!end.isAfter(now)) return 'Pickup must end later today.';
    return null;
  }
}
