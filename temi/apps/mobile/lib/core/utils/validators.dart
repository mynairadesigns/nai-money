/// Shared `TextFormField` validators.
///
/// Every form in the app returns `null` for valid input and a short,
/// sentence-case message otherwise, so error copy stays consistent across
/// screens instead of being reinvented per form.
class Validators {
  Validators._();

  /// Length ceilings for free-text fields. Names land in list rows and
  /// chart labels; notes are mirrored to Firestore on every write, so
  /// both need a bound.
  static const int nameMaxLength = 60;
  static const int noteMaxLength = 280;

  /// Largest single monetary value we accept. Beyond this, `double`
  /// formatting degrades and the value is almost certainly a typo or a
  /// mis-pasted account number.
  static const double amountMax = 999999999.99;

  /// Deliberately permissive: one `@`, a dot-bearing domain, no spaces.
  /// Stricter patterns reject valid addresses; the real check is the
  /// verification email.
  static final RegExp _emailPattern = RegExp(
    r'^[\w.!#$%&*+/=?^`{|}~-]+@[\w-]+(\.[\w-]+)+$',
  );

  /// Non-empty after trimming, capped at [maxLength].
  static String? requiredText(
    String? value, {
    String label = 'This field',
    int maxLength = nameMaxLength,
  }) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '$label is required';
    if (v.length > maxLength) {
      return '$label must be $maxLength characters or fewer';
    }
    return null;
  }

  /// Optional free text with a length ceiling.
  static String? optionalText(
    String? value, {
    String label = 'This field',
    int maxLength = noteMaxLength,
  }) {
    final v = value?.trim() ?? '';
    if (v.length > maxLength) {
      return '$label must be $maxLength characters or fewer';
    }
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_emailPattern.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Firebase enforces 6 characters server-side; checking it here turns a
  /// generic post-submit SnackBar into an inline error before the call.
  static String? password(String? value, {int minLength = 6}) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < minLength) {
      return 'Password must be at least $minLength characters';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  /// Parses a money field. Rejects unparseable text outright rather than
  /// letting `tryParse(...) ?? 0` silently save a zero.
  static String? amount(
    String? value, {
    String label = 'Amount',
    bool allowZero = false,
    bool allowNegative = false,
    double? max,
  }) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '$label is required';
    final parsed = double.tryParse(v);
    if (parsed == null) return 'Enter a valid number';
    if (!parsed.isFinite) return 'Enter a valid number';
    if (!allowNegative && parsed < 0) return "$label can't be negative";
    if (!allowZero && parsed == 0) return '$label must be greater than 0';
    final ceiling = max ?? amountMax;
    if (parsed.abs() > ceiling) return '$label is too large';
    return null;
  }

  /// Same as [amount] but tolerates an empty field.
  static String? optionalAmount(
    String? value, {
    String label = 'Amount',
    bool allowZero = true,
    bool allowNegative = false,
    double? max,
  }) {
    if ((value?.trim() ?? '').isEmpty) return null;
    return amount(
      value,
      label: label,
      allowZero: allowZero,
      allowNegative: allowNegative,
      max: max,
    );
  }

  /// Whole number ≥ [min], used for recurring intervals.
  static String? positiveInt(
    String? value, {
    String label = 'Value',
    int min = 1,
    int max = 999,
  }) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '$label is required';
    final parsed = int.tryParse(v);
    if (parsed == null) return 'Enter a whole number';
    if (parsed < min) return '$label must be at least $min';
    if (parsed > max) return '$label must be $max or less';
    return null;
  }
}
