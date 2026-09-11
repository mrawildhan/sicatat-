import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Skala teks tunggal untuk seluruh layar aplikasi.
///
/// Beranda menjadi acuan: judul bagian tetap tegas, judul kartu mudah dipindai,
/// dan teks pendukung tidak bersaing dengan informasi utama.
class AppTextStyles {
  static const pageTitle = TextStyle(
    fontSize: 24,
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
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      brightness: Brightness.light,
      surface: AppColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: AppColors.green,
        onPrimary: Colors.white,
        secondary: AppColors.orange,
        tertiary: AppColors.greenDark,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.surface,
      fontFamily: 'Arial',
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
  }
}
