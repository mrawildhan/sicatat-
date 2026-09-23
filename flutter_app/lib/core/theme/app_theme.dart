import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pdf/pdf_theme.dart';

class AppColors {
  // SICATAT brand palette: green is intentionally dominant across the app.
  static const green = Color(0xFF176B4D);
  static const greenDark = Color(0xFF0B3D2E);
  static const greenDeep = Color(0xFF06291F);
  static const mint = Color(0xFFE7F3ED);
  static const greenSurface = Color(0xFFF2F8F4);
  static const orange = Color(0xFFE8833B);
  static const ink = Color(0xFF17221D);
  static const muted = Color(0xFF6D7A73);
  static const surface = greenSurface;
  static const line = Color(0xFFDCE7E0);
  static const warning = Color(0xFFF2B84B);
  static const danger = Color(0xFFD85B52);
}

/// One type ladder for the whole app: 22 / 20 / 18 / 15 / 14 / 12 / 11.
///
/// Screens used to pick their own sizes, so the same kind of heading appeared
/// at 22 on one page and 26 on another, and supporting text drifted between 9
/// and 13. Every new text style must reuse one of these rather than introduce
/// a size in between.
class AppTextStyles {
  static const pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w900,
    height: 1.15,
  );
  static const sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w900,
    height: 1.2,
  );
  static const cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    height: 1.25,
  );
  static const body = TextStyle(fontSize: 14, height: 1.35);
  static const supporting = TextStyle(
    color: AppColors.muted,
    fontSize: 12,
    height: 1.3,
  );
  static const metric = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w900,
    height: 1.15,
  );

  /// Chips, status badges, and micro-labels under a metric. The smallest size
  /// the app is allowed to use.
  static const badge = TextStyle(fontSize: 11, height: 1.2);
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      brightness: Brightness.light,
      surface: AppColors.surface,
    );
    final ThemeData theme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: AppColors.green,
        onPrimary: Colors.white,
        secondary: AppColors.orange,
        tertiary: AppColors.greenDark,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: appFontFamily,
      textTheme: const TextTheme(
        displaySmall: AppTextStyles.pageTitle,
        headlineSmall: AppTextStyles.pageTitle,
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        titleMedium: AppTextStyles.cardTitle,
        bodyLarge: AppTextStyles.body,
        bodyMedium: AppTextStyles.body,
        bodySmall: AppTextStyles.supporting,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.greenDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: AppColors.greenDark,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.mint,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? AppColors.greenDark : AppColors.muted,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.green, width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
    // ListTile does not read the text theme's body styles the way Text does:
    // by default its title is bodyLarge with wide Material letter spacing and
    // its subtitle is 14, so list rows looked larger than the cards on
    // Beranda and Suhu.  Give them the same card title and supporting text.
    final TextStyle base = theme.textTheme.bodyMedium!;
    return theme.copyWith(
      listTileTheme: ListTileThemeData(
        titleTextStyle: base
            .merge(AppTextStyles.cardTitle)
            .copyWith(color: AppColors.ink),
        subtitleTextStyle: base.merge(AppTextStyles.supporting),
        leadingAndTrailingTextStyle: base.merge(AppTextStyles.supporting),
      ),
    );
  }
}
