import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

/// SICATAT uses one typeface everywhere: Roboto (SIL OFL 1.1, see
/// assets/fonts/OFL.txt), chosen by the owner on 2026-09-23.  The app renders
/// it and every PDF embeds it.  The Excel export carries no font file and
/// names Aptos, the Office default, which the owner chose for Excel.  Aptos
/// itself may only be used inside Office, so never bundle it here.
///
/// This file stays free of Flutter imports so `dart run tool/...` scripts can
/// build the same PDFs.
const String appFontFamily = 'Roboto';
const String appFontRegularAsset = 'assets/fonts/Roboto-Regular.ttf';
const String appFontBoldAsset = 'assets/fonts/Roboto-Bold.ttf';

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
