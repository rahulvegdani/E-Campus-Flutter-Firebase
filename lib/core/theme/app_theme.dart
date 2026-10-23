import 'package:flutter/material.dart';

abstract final class AppColors {
  static const surface = Color(0xFFF9F8F6);
  static const onSurface = Color(0xFF1A1A1A);
  static const card = Color(0xFFFFFFFF);
  static const tertiarySurface = Color(0xFFF0EEE9);
  static const brand = Color(0xFF2E5B44);
  static const brandSecondary = Color(0xFFD4A373);
  static const brandTertiary = Color(0xFFE7EFE9);
  static const success = Color(0xFF386641);
  static const warning = Color(0xFFBC6C25);
  static const error = Color(0xFF9B2226);
  static const info = Color(0xFF457B9D);
  static const border = Color(0xFFE2DFD8);
  static const divider = Color(0xFFEFECE6);
  static const muted = Color(0xFF767676);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: Brightness.light,
    surface: AppColors.surface,
  ).copyWith(
    primary: AppColors.brand,
    onPrimary: Colors.white,
    secondary: AppColors.brandSecondary,
    surfaceContainerHighest: AppColors.tertiarySurface,
    error: AppColors.error,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    fontFamily: 'sans',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.brand, width: 2),
      ),
    ),
  );
}
