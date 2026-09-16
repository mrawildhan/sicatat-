// Regenerates the printable guide that ships in docs/.
//
// Run from flutter_app/:  dart run tool/generate_guide_pdf.dart
//
// It reads the same content the app shows (lib/features/guide/guide_content.dart),
// so the file in docs/ can never drift from the in-app guide again.
import 'dart:io';
import 'dart:typed_data';

import 'package:sicatat_flutter/features/guide/guide_content.dart';

Future<void> main() async {
  final Uint8List bytes = await buildGuidePdfBytes();
  final File output = File('docs/Panduan-Pengguna-SICATAT.pdf');
  await output.writeAsBytes(bytes);
  stdout.writeln(
    'Wrote ${output.path} (${bytes.length} bytes, ${guideGroups.length} groups)',
  );
}
