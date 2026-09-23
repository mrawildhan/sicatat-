import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_theme.dart';

pw.ThemeData? _cachedTheme;

/// The PDF theme with the app font, loaded once from the bundled assets.
Future<pw.ThemeData> loadPdfTheme() async {
  final pw.ThemeData? cached = _cachedTheme;
  if (cached != null) return cached;
  final pw.ThemeData theme = pdfThemeFromFontBytes(
    regular: await rootBundle.load(appFontRegularAsset),
    bold: await rootBundle.load(appFontBoldAsset),
  );
  return _cachedTheme = theme;
}

/// Shows the bundled font's licence on Flutter's licence page.
void registerAppFontLicense() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(<String>[
      'Poppins',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
}
