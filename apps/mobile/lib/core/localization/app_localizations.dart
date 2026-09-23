import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Runtime ARB loader.
///
/// Translations live in standard `.arb` files under `lib/l10n/`, the same
/// format `flutter gen-l10n` consumes, so a translator's workflow is unchanged.
/// They are loaded at runtime instead of code-generated, which keeps the build
/// free of a generation step and makes adding a language a matter of dropping
/// in one file and listing its locale in [supportedLocales].
class AppLocalizations {
  AppLocalizations(this.locale, this._strings);

  final Locale locale;
  final Map<String, String> _strings;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final AppLocalizations? instance =
        Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(instance != null, 'No AppLocalizations found in context');
    return instance!;
  }

  /// True when the active locale reads right-to-left.
  bool get isRtl => Bidi.isRtlLanguage(locale.languageCode);

  /// Look up [key], substituting `{placeholder}` values from [args].
  ///
  /// A missing key returns the key itself rather than throwing: a translation
  /// gap should look wrong in the UI, never crash the screen.
  String t(String key, [Map<String, Object?>? args]) {
    String value = _strings[key] ?? key;
    if (args != null && args.isNotEmpty) {
      args.forEach((String name, Object? replacement) {
        value = value.replaceAll('{$name}', '$replacement');
      });
    }
    return value;
  }

  static Future<AppLocalizations> load(Locale locale) async {
    final String languageCode = supportedLocales
            .map((Locale supported) => supported.languageCode)
            .contains(locale.languageCode)
        ? locale.languageCode
        : 'en';

    final Map<String, String> strings = await _loadArb(languageCode);
    if (languageCode != 'en') {
      // Fall back to English for any key a translation hasn't caught up on.
      final Map<String, String> fallback = await _loadArb('en');
      for (final MapEntry<String, String> entry in fallback.entries) {
        strings.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return AppLocalizations(Locale(languageCode), strings);
  }

  static final Map<String, Map<String, String>> _cache =
      <String, Map<String, String>>{};

  static Future<Map<String, String>> _loadArb(String languageCode) async {
    final Map<String, String>? cached = _cache[languageCode];
    if (cached != null) {
      return Map<String, String>.of(cached);
    }

    final String raw =
        await rootBundle.loadString('lib/l10n/app_$languageCode.arb');
    final Map<String, dynamic> decoded =
        json.decode(raw) as Map<String, dynamic>;

    final Map<String, String> strings = <String, String>{};
    for (final MapEntry<String, dynamic> entry in decoded.entries) {
      // Keys starting with '@' are ARB metadata, not translations.
      if (entry.key.startsWith('@')) continue;
      if (entry.value is String) strings[entry.key] = entry.value as String;
    }

    _cache[languageCode] = Map<String, String>.of(strings);
    return strings;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales
      .map((Locale supported) => supported.languageCode)
      .contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations.load(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// `context.l10n.t('navHome')` at call sites.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Minimal bidi helper so the app doesn't depend on `intl` for one check.
class Bidi {
  const Bidi._();

  static const Set<String> _rtlLanguages = <String>{
    'ar',
    'fa',
    'he',
    'iw',
    'ur',
    'ps',
    'sd',
    'ug',
    'yi',
  };

  static bool isRtlLanguage(String languageCode) =>
      _rtlLanguages.contains(languageCode.toLowerCase());
}
