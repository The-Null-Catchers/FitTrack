import 'package:fittrack/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email', () {
    test('accepts ordinary addresses', () {
      expect(Validators.email('sam@example.com'), isNull);
      expect(Validators.email('  sam+gym@example.co.uk '), isNull);
    });

    test('rejects blanks and malformed addresses', () {
      expect(Validators.email(''), 'authEmailRequired');
      expect(Validators.email(null), 'authEmailRequired');
      expect(Validators.email('not-an-email'), 'authEmailInvalid');
      expect(Validators.email('missing@domain'), 'authEmailInvalid');
    });
  });

  group('password', () {
    test('accepts a mixed password of sufficient length', () {
      expect(Validators.password('StrongPass1'), isNull);
    });

    test('mirrors the server rules', () {
      expect(Validators.password(''), 'authPasswordRequired');
      expect(Validators.password('short1'), 'authPasswordTooShort');
      expect(Validators.password('alllowercase'), 'authPasswordTooSimple');
      expect(Validators.password('12345678'), 'authPasswordTooSimple');
    });
  });

  group('decimal parsing', () {
    test('accepts both decimal separators', () {
      expect(Validators.parseDecimal('82.5'), 82.5);
      expect(Validators.parseDecimal('82,5'), 82.5);
    });

    test('returns null for empty or invalid input', () {
      expect(Validators.parseDecimal(''), isNull);
      expect(Validators.parseDecimal(null), isNull);
      expect(Validators.parseDecimal('abc'), isNull);
    });
  });
}
