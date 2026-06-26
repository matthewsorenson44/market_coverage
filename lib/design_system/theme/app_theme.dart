import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

class AppTheme {
  static ThemeData darkTheme() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.textPrimaryDark,
          secondary: AppColors.accent,
          onSecondary: AppColors.bgDark,
          error: AppColors.danger,
          onError: AppColors.textPrimaryDark,
          surface: AppColors.surfaceDark,
          onSurface: AppColors.textPrimaryDark,
        );

    return _theme(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      backgroundColor: AppColors.bgDark,
      surfaceColor: AppColors.surfaceDark,
      elevatedSurfaceColor: AppColors.surfaceElevatedDark,
      borderColor: AppColors.borderDark,
      primaryTextColor: AppColors.textPrimaryDark,
      secondaryTextColor: AppColors.textSecondaryDark,
      dark: true,
    );
  }

  static ThemeData lightTheme() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.surfaceLight,
          secondary: AppColors.accent,
          onSecondary: AppColors.textPrimaryLight,
          error: AppColors.danger,
          onError: AppColors.surfaceLight,
          surface: AppColors.surfaceLight,
          onSurface: AppColors.textPrimaryLight,
        );

    return _theme(
      brightness: Brightness.light,
      colorScheme: colorScheme,
      backgroundColor: AppColors.bgLight,
      surfaceColor: AppColors.surfaceLight,
      elevatedSurfaceColor: AppColors.surfaceElevatedLight,
      borderColor: AppColors.borderLight,
      primaryTextColor: AppColors.textPrimaryLight,
      secondaryTextColor: AppColors.textSecondaryLight,
      dark: false,
    );
  }

  static ThemeData _theme({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required Color backgroundColor,
    required Color surfaceColor,
    required Color elevatedSurfaceColor,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required bool dark,
  }) {
    final borderRadius = BorderRadius.circular(AppSpacing.buttonBorderRadius);
    final textTheme = TextTheme(
      displayLarge: AppTypography.displayLarge(dark: dark),
      displayMedium: AppTypography.displayMedium(dark: dark),
      headlineLarge: AppTypography.headingLarge(dark: dark),
      headlineMedium: AppTypography.headingMedium(dark: dark),
      headlineSmall: AppTypography.headingSmall(dark: dark),
      bodyLarge: AppTypography.bodyLarge(dark: dark),
      bodyMedium: AppTypography.bodyMedium(dark: dark),
      bodySmall: AppTypography.bodySmall(dark: dark),
      labelLarge: AppTypography.labelLarge(dark: dark),
      labelMedium: AppTypography.labelMedium(dark: dark),
      labelSmall: AppTypography.labelSmall(dark: dark),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: GoogleFonts.inter().fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundColor,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: primaryTextColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.headingLarge(
          color: primaryTextColor,
          dark: dark,
        ),
        iconTheme: IconThemeData(color: primaryTextColor),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardBorderRadius),
          side: BorderSide(color: borderColor),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: secondaryTextColor,
        selectedLabelStyle: AppTypography.labelSmall(
          color: AppColors.primary,
          dark: dark,
        ),
        unselectedLabelStyle: AppTypography.labelSmall(
          color: secondaryTextColor,
          dark: dark,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surfaceLight,
          minimumSize: const Size(0, AppSpacing.touchTarget),
          textStyle: AppTypography.labelLarge(color: AppColors.surfaceLight),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surfaceLight,
          minimumSize: const Size(0, AppSpacing.touchTarget),
          textStyle: AppTypography.labelLarge(color: AppColors.surfaceLight),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, AppSpacing.touchTarget),
          textStyle: AppTypography.labelLarge(color: AppColors.primary),
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, AppSpacing.touchTarget),
          textStyle: AppTypography.labelLarge(color: AppColors.primary),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevatedSurfaceColor,
        labelStyle: AppTypography.bodyMedium(
          color: secondaryTextColor,
          dark: dark,
        ),
        hintStyle: AppTypography.bodyMedium(
          color: secondaryTextColor,
          dark: dark,
        ),
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? AppColors.surfaceElevatedDark
            : AppColors.bgDark,
        contentTextStyle: AppTypography.bodyMedium(
          color: AppColors.textPrimaryDark,
        ),
        insetPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.bottomNavHeight + AppSpacing.lg,
        ),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cardBorderRadius),
          ),
        ),
      ),
    );
  }
}
