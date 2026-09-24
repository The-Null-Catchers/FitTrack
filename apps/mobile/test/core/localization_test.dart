import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the two things that silently rot in a bilingual app: a key that
/// exists in one language but not the other, and a string that never made it
/// out of the source into the ARB files at all.
void main() {
  late Map<String, dynamic> en;
  late Map<String, dynamic> ar;

  setUpAll(() {
    en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    ar = jsonDecode(File('lib/l10n/app_ar.arb').readAsStringSync())
        as Map<String, dynamic>;
  });

  Set<String> keys(Map<String, dynamic> arb) =>
      arb.keys.where((String k) => !k.startsWith('@')).toSet();

  test('both languages define exactly the same keys', () {
    expect(keys(en).difference(keys(ar)), isEmpty,
        reason: 'keys missing from Arabic');
    expect(keys(ar).difference(keys(en)), isEmpty,
        reason: 'keys missing from English');
  });

  test('no value is empty in either language', () {
    for (final String k in keys(en)) {
      expect('${en[k]}'.trim(), isNotEmpty, reason: 'empty English value: $k');
      expect('${ar[k]}'.trim(), isNotEmpty, reason: 'empty Arabic value: $k');
    }
  });

  test('Arabic is actually Arabic, not English left in place', () {
    final RegExp arabic = RegExp(r'[؀-ۿ]');
    // Keys whose value is legitimately identical in both languages.
    const Set<String> exempt = <String>{
      'appName',
      'languageEnglish',
      'languageArabic',
      'brandName',
    };
    final List<String> untranslated = <String>[];
    for (final String k in keys(ar)) {
      if (exempt.contains(k)) continue;
      final String v = '${ar[k]}';
      // A value with letters but no Arabic script is still English.
      if (RegExp(r'[A-Za-z]{4,}').hasMatch(v) && !arabic.hasMatch(v)) {
        untranslated.add('$k = "$v"');
      }
    }
    expect(untranslated, isEmpty,
        reason:
            'Arabic values that are still English:\n${untranslated.join('\n')}');
  });

  test('every l10n key used in the source exists in both ARB files', () {
    final RegExp used = RegExp(r"""\.t\(\s*'([A-Za-z0-9_]+)'""");
    final Set<String> referenced = <String>{};
    for (final FileSystemEntity f
        in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final RegExpMatch m in used.allMatches(f.readAsStringSync())) {
        referenced.add(m.group(1)!);
      }
    }
    expect(referenced, isNotEmpty, reason: 'the scan found no keys at all');
    final Set<String> missing = referenced.difference(keys(en));
    expect(missing, isEmpty,
        reason: 'used in code but absent from the ARB files: $missing');
  });

  test('no user-facing string is hardcoded in the widgets we own', () {
    // Text('...') with a literal, rather than going through l10n.
    final RegExp literal = RegExp(
        r"""(?:Text|label:\s*Text|title:\s*Text|subtitle:\s*Text)\(\s*(?:const\s+)?['"]([^'"]{4,})['"]""");
    // Language names are shown in their own language on purpose; numbers and
    // URLs are not translatable.
    const Set<String> allowed = <String>{
      'System',
      'English',
      'العربية',
    };
    final List<String> offenders = <String>[];
    for (final FileSystemEntity f
        in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final RegExpMatch m in literal.allMatches(f.readAsStringSync())) {
        final String text = m.group(1)!;
        if (allowed.contains(text)) continue;
        // Interpolated strings compose already-translated values and
        // numbers; they are not untranslated copy.
        if (text.contains(r'$')) continue;
        if (text.startsWith('http') ||
            RegExp(r'^[\d\s+\-.,%]+$').hasMatch(text)) {
          continue;
        }
        offenders.add('${f.path}: "$text"');
      }
    }
    expect(offenders, isEmpty,
        reason: 'hardcoded user-facing strings:\n${offenders.join('\n')}');
  });
}
