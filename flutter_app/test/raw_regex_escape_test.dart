import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'raw-string regular expressions do not double-escape character classes',
    () {
      // In a Dart raw string `r'\\d'` is a literal backslash followed by "d".
      // That silently rejected every valid shift time (07:00) and roster date
      // (2026-09-14), so neither could be saved from the website.
      final RegExp doubleEscapedClass = RegExp(
        r"""RegExp\(\s*r(['"]).*?\\\\[dDsSwWbB].*?\1""",
      );
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final List<String> lines = entity.readAsLinesSync();
        for (int index = 0; index < lines.length; index++) {
          if (doubleEscapedClass.hasMatch(lines[index])) {
            offenders.add(
              '${entity.path}:${index + 1}: ${lines[index].trim()}',
            );
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'Use a single backslash inside r\'...\'.',
      );
    },
  );

  test('shift time and roster date patterns accept valid values', () {
    final RegExp time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    final RegExp date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    expect(time.hasMatch('07:00'), isTrue);
    expect(time.hasMatch('19:30'), isTrue);
    expect(time.hasMatch('24:00'), isFalse);
    expect(date.hasMatch('2026-09-14'), isTrue);
    expect(date.hasMatch('14-09-2026'), isFalse);
  });
}
