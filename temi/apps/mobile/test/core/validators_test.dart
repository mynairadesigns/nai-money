import 'package:flutter_test/flutter_test.dart';

import 'package:temi_finance/core/utils/validators.dart';

/// Shared form validators. The regressions these lock down: an amount
/// field that fell through `tryParse(...) ?? 0` and silently saved a
/// zero, and auth fields that no-oped on invalid input with no message.
void main() {
  group('amount', () {
    test('rejects empty, unparseable, zero, and negative by default', () {
      expect(Validators.amount(''), isNotNull);
      expect(Validators.amount('   '), isNotNull);
      expect(Validators.amount('abc'), isNotNull);
      expect(Validators.amount('12abc'), isNotNull);
      expect(Validators.amount('0'), isNotNull);
      expect(Validators.amount('-5'), isNotNull);
    });

    test('rejects non-finite input', () {
      // `double.tryParse` happily returns these.
      expect(Validators.amount('Infinity'), isNotNull);
      expect(Validators.amount('NaN'), isNotNull);
    });

    test('accepts a positive number, with or without decimals', () {
      expect(Validators.amount('5'), isNull);
      expect(Validators.amount('12.34'), isNull);
      expect(Validators.amount(' 12.34 '), isNull);
    });

    test('honours allowZero / allowNegative for opening balances', () {
      expect(Validators.amount('0', allowZero: true), isNull);
      expect(
        Validators.amount('-250', allowZero: true, allowNegative: true),
        isNull,
      );
    });

    test('rejects values past the ceiling in both directions', () {
      expect(Validators.amount('1e30'), isNotNull);
      expect(
        Validators.amount('-1e30', allowNegative: true),
        isNotNull,
      );
      expect(Validators.amount('100', max: 50), isNotNull);
    });

    test('optionalAmount tolerates empty but not garbage', () {
      expect(Validators.optionalAmount(''), isNull);
      expect(Validators.optionalAmount(null), isNull);
      expect(Validators.optionalAmount('abc'), isNotNull);
      expect(Validators.optionalAmount('-1'), isNotNull);
      expect(Validators.optionalAmount('1200'), isNull);
    });
  });

  group('email', () {
    test('rejects blank and malformed addresses', () {
      for (final bad in ['', '  ', 'nope', 'a@b', 'a b@c.com', '@c.com']) {
        expect(Validators.email(bad), isNotNull, reason: 'accepted "$bad"');
      }
    });

    test('accepts ordinary addresses, ignoring surrounding whitespace', () {
      for (final ok in [
        'a@b.com',
        ' user.name+tag@sub.example.co ',
        'x_y@example.io',
      ]) {
        expect(Validators.email(ok), isNull, reason: 'rejected "$ok"');
      }
    });
  });

  group('password', () {
    test('requires a value and the Firebase 6-character minimum', () {
      expect(Validators.password(''), isNotNull);
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });

    test('confirmPassword matches exactly', () {
      expect(Validators.confirmPassword('', 'secret1'), isNotNull);
      expect(Validators.confirmPassword('secret2', 'secret1'), isNotNull);
      expect(Validators.confirmPassword('secret1', 'secret1'), isNull);
    });
  });

  group('text', () {
    test('requiredText rejects blank and whitespace-only input', () {
      expect(Validators.requiredText(null), isNotNull);
      expect(Validators.requiredText('   '), isNotNull);
      expect(Validators.requiredText('Groceries'), isNull);
    });

    test('both text validators enforce their length ceiling', () {
      final longName = 'a' * (Validators.nameMaxLength + 1);
      final longNote = 'a' * (Validators.noteMaxLength + 1);
      expect(Validators.requiredText(longName), isNotNull);
      expect(Validators.optionalText(longNote), isNotNull);
      expect(Validators.optionalText(''), isNull);
    });
  });

  group('positiveInt', () {
    test('requires a whole number at or above the minimum', () {
      expect(Validators.positiveInt(''), isNotNull);
      expect(Validators.positiveInt('1.5'), isNotNull);
      expect(Validators.positiveInt('0'), isNotNull);
      expect(Validators.positiveInt('1000'), isNotNull);
      expect(Validators.positiveInt('3'), isNull);
    });
  });
}
