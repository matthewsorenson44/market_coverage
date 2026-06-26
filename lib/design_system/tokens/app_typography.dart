import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTypography {
  static TextStyle displayLarge({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.1,
      letterSpacing: 0,
    );
  }

  static TextStyle displayMedium({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.15,
      letterSpacing: 0,
    );
  }

  static TextStyle headingLarge({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
  }

  static TextStyle headingMedium({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
  }

  static TextStyle headingSmall({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 15,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
  }

  static TextStyle bodyLarge({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.45,
    );
  }

  static TextStyle bodyMedium({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.4,
    );
  }

  static TextStyle bodySmall({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.35,
    );
  }

  static TextStyle labelLarge({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: 0.2,
    );
  }

  static TextStyle labelMedium({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
  }

  static TextStyle labelSmall({Color? color, bool dark = true}) {
    return GoogleFonts.inter(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );
  }

  static TextStyle monoLarge({Color? color, bool dark = true}) {
    return GoogleFonts.jetBrainsMono(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
  }

  static TextStyle monoMedium({Color? color, bool dark = true}) {
    return GoogleFonts.jetBrainsMono(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
  }

  static TextStyle hudDisplay({Color? color, bool dark = true}) {
    return GoogleFonts.jetBrainsMono(
      color:
          color ??
          (dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );
  }
}
