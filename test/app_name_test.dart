import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app is called AvePlay. This asserts nothing the reader can see still
/// calls it Mangayomi.
///
/// Every localisation file is read from disk at runtime rather than listed
/// here, so a locale added later is covered by this the day it lands — and a
/// new locale, translated from an older source, is exactly where the old name
/// comes back.
void main() {
  group('app name', () {
    /// The internal identifiers, which are deliberately NOT renamed:
    ///
    ///  - the Dart package name, which is every import path in the project
    ///  - the Android applicationId, which is the app's identity to the OS:
    ///    changing it means the new build will not install over an existing
    ///    one and the library it carries is orphaned
    ///  - `Mangayomi/local`, the on-disk folder people already keep files in
    ///
    /// None of these are shown to the reader, and all three are expensive or
    /// destructive to change.
    test('no user-visible string calls the app Mangayomi', () {
      final offenders = <String>[];

      for (final file in Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Keys and metadata (@key entries) are not shown to anyone; only the
          // translated value is. Both sit on one line in these files.
          final value = _valueOf(line);
          if (value == null) continue;
          if (value.toLowerCase().contains('mangayomi')) {
            offenders.add('${file.path}:${i + 1}: $line');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These strings are shown to the reader and still say Mangayomi:\n'
            '${offenders.join('\n')}',
      );
    });

    /// The .arb files are not the only place a name reaches the screen: two
    /// strings lived directly in Dart, and a scan of the translations alone
    /// would have passed while the app still said Mangayomi on a crash screen
    /// and in the share sheet.
    test('no Dart string literal shown to the reader says Mangayomi', () {
      final offenders = <String>[];

      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Comments explain code and are not rendered; only literals are.
          final code = line.split('//').first;
          for (final literal in RegExp(r'''(['"])(.*?)\1''').allMatches(code)) {
            final text = literal.group(2)!;
            if (!text.contains('Mangayomi') && !text.contains('MangaYomi')) {
              continue;
            }
            // Exempt where the name is a location rather than a label: the
            // folders people already keep files in, and the bare folder name
            // those paths are built from. Renaming any of them orphans an
            // existing library without changing a word the reader sees.
            //
            // The bare name is exempt only as the WHOLE literal. Matching it
            // as a substring would exempt every string containing the word —
            // every string this test exists to find — and the check would pass
            // for ever while reporting nothing.
            final isPathSegment =
                text.contains('Mangayomi/') || text.contains('Mangayomi\\');
            if (text == 'Mangayomi' || isPathSegment) continue;
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'These literals still carry the old name:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the task-switcher title is AvePlay', () {
      // MaterialApp.title is what Android shows on the recents card. It
      // overrides android:label, so the manifest being right is not enough.
      final main = File('lib/main.dart').readAsStringSync();
      final title = RegExp(r"""title:\s*'([^']*)'""").firstMatch(main);
      expect(title, isNotNull, reason: 'no MaterialApp title found in main.dart');
      expect(title!.group(1), 'AvePlay');
    });
  });
}

/// The translated value on an .arb line, or null when the line carries none.
///
/// An .arb file is JSON, one `"key": "value",` per line. The key can itself
/// contain the app name harmlessly (nothing renders a key), so this returns
/// the value side only, and skips `@key` metadata entries entirely.
String? _valueOf(String line) {
  final trimmed = line.trim();
  if (trimmed.startsWith('"@')) return null;
  final match = RegExp(r'^"[^"]*"\s*:\s*"(.*)"\s*,?$').firstMatch(trimmed);
  return match?.group(1);
}
