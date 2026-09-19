/// Form validation shared by the auth and profile screens.
///
/// Messages are keys into the localisation bundle, not English strings, so the
/// same validator works in both languages.
class Validators {
  const Validators._();

  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  /// Returns a localisation key, or `null` when the value is acceptable.
  static String? email(String? value) {
    final String trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'authEmailRequired';
    if (!_email.hasMatch(trimmed)) return 'authEmailInvalid';
    return null;
  }

  static String? password(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'authPasswordRequired';
    if (password.length < 8) return 'authPasswordTooShort';
    // Mirrors the server rule: letters alone or digits alone are rejected.
    final bool onlyLetters = RegExp(r'^[A-Za-z]+$').hasMatch(password);
    final bool onlyDigits = RegExp(r'^\d+$').hasMatch(password);
    if (onlyLetters || onlyDigits) return 'authPasswordTooSimple';
    return null;
  }

  static String? required(String? value, String messageKey) =>
      (value ?? '').trim().isEmpty ? messageKey : null;

  static String? fullName(String? value) => required(value, 'authNameRequired');

  /// Parses a decimal entered with either a dot or a comma.
  static double? parseDecimal(String? value) {
    if (value == null) return null;
    final String normalised = value.trim().replaceAll(',', '.');
    if (normalised.isEmpty) return null;
    return double.tryParse(normalised);
  }

  static int? parseInt(String? value) {
    if (value == null) return null;
    return int.tryParse(value.trim());
  }
}
