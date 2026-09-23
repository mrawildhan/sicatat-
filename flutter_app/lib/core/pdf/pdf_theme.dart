import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

/// SICATAT uses one typeface everywhere: Figtree (SIL OFL 1.1, see
/// assets/fonts/OFL.txt), chosen by the owner on 2026-09-23 as the free
/// look-alike of Aptos.  Aptos itself is a Microsoft font that may only be used
/// inside Office, so the app renders Figtree and every PDF embeds it, while the
/// Excel export, which carries no font file, names Aptos.
///
/// This file stays free of Flutter imports so `dart run tool/...` scripts can
/// build the same PDFs.
const String appFontFamily = 'Figtree';
const String appFontRegularAsset = 'assets/fonts/Figtree-Regular.ttf';
const String appFontBoldAsset = 'assets/fonts/Figtree-Bold.ttf';

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
