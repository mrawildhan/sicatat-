import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

/// SICATAT uses one typeface everywhere: Poppins (SIL OFL 1.1, see
/// assets/fonts/OFL.txt), chosen by the owner on 2026-09-23.  The app renders
/// it, every PDF embeds it, and the Excel export names it too.
///
/// This file stays free of Flutter imports so `dart run tool/...` scripts can
/// build the same PDFs.
const String appFontFamily = 'Poppins';
const String appFontRegularAsset = 'assets/fonts/Poppins-Regular.ttf';
const String appFontBoldAsset = 'assets/fonts/Poppins-Bold.ttf';

/// A PDF theme on the app font.  The PDF standard fonts (Helvetica) looked
/// different from the app and could not draw characters such as "≥" or "–".
pw.ThemeData pdfThemeFromFontBytes({
  required ByteData regular,
  required ByteData bold,
}) {
  final pw.Font base = pw.Font.ttf(regular);
  final pw.Font strong = pw.Font.ttf(bold);
  return pw.ThemeData.withFont(
    base: base,
    bold: strong,
    italic: base,
    boldItalic: strong,
  );
}
