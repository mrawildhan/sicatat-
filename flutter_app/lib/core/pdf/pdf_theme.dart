import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

/// SICATAT uses one typeface everywhere: Liberation Sans, which has Arial's
/// exact metrics and look but may be bundled (SIL OFL 1.1, see
/// assets/fonts/OFL.txt).  The app renders it, every PDF embeds it, and the
/// Excel export names Arial, which Excel always has and which lines up with
/// it character for character.
///
/// This file stays free of Flutter imports so `dart run tool/...` scripts can
/// build the same PDFs.
const String appFontFamily = 'LiberationSans';
const String appFontRegularAsset = 'assets/fonts/LiberationSans-Regular.ttf';
const String appFontBoldAsset = 'assets/fonts/LiberationSans-Bold.ttf';

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
