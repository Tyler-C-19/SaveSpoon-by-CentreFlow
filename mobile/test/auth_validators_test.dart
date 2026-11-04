import 'package:flutter_test/flutter_test.dart';
import 'package:savespoon/features/auth/domain/auth_validators.dart';

void main() {
  test('password needs 8+ characters with a letter and a number', () {
    expect(AuthValidators.password('Secret123'), isNull);
    expect(AuthValidators.password('Sec1'), isNotNull);
    expect(AuthValidators.password('lettersonly'), isNotNull);
    expect(AuthValidators.password('12345678'), isNotNull);
    expect(AuthValidators.password('a1' * 40), isNotNull);
  });

  test('email and phone formats', () {
    expect(AuthValidators.email(' person@example.com '), isNull);
    expect(AuthValidators.email('nope'), isNotNull);
    expect(AuthValidators.phone('012-3456789'), isNull);
    expect(AuthValidators.phone('+60 12 345 6789'), isNull);
    expect(AuthValidators.phone('abc'), isNotNull);
  });

  test('code must be exactly 6 digits', () {
    expect(AuthValidators.code('123456'), isNull);
    expect(AuthValidators.code('12345'), isNotNull);
    expect(AuthValidators.code('12345a'), isNotNull);
  });
}
