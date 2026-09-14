import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Supabase order() call states its direction explicitly', () {
    // postgrest-dart sorts DESCENDING when `ascending` is omitted (unlike SQL
    // and postgrest-js). That silently reversed lists such as sites, reminders
    // and warehouse stock, and `.order(...).limit(100)` returned the last rows.
    final RegExp missingDirection = RegExp(
      r"""\.order\(\s*(['"])[A-Za-z0-9_.]+\1\s*\)""",
    );
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final List<String> lines = entity.readAsLinesSync();
      for (int index = 0; index < lines.length; index++) {
        if (missingDirection.hasMatch(lines[index])) {
          offenders.add('${entity.path}:${index + 1}: ${lines[index].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Add `ascending: true` or `ascending: false` to each order().',
    );
  });
}
