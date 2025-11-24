import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// ShazaPiano Theme
class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      
      // Colors
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: AppColors.textPrimary,
        onSecondary: AppColors.textPrimary,
        onSurface: AppColors.textPrimary,
        onError: AppColors.textPrimary,
      ),

      // Text Theme
      textTheme: TextTheme(
        displayLarge: AppTextStyles.display,
        titleLarge: AppTextStyles.title,
        bodyLarge: AppTextStyles.body,
        bodySmall: AppTextStyles.caption,
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTextStyles.title.copyWith(
          color: AppColors.textPrimary,
        ),
      ),

      // Card
      cardTheme: CardTheme(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  // Private constructor
  AppTheme._();
}

