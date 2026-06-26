import 'package:flutter/material.dart';

import '../tokens/app_animations.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

enum AppChipVariant { filter, status, tag }

class AppChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? selectedColor;
  final AppChipVariant variant;

  const AppChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.icon,
    this.selectedColor,
    this.variant = AppChipVariant.filter,
  }) : assert(
         variant != AppChipVariant.status || selectedColor != null,
         'selectedColor is required for status chips.',
       );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = _AppChipColors.forState(
      variant: variant,
      isSelected: isSelected,
      selectedColor: selectedColor,
      dark: dark,
    );
    final content = AnimatedContainer(
      duration: AppAnimations.fastDuration,
      curve: AppAnimations.defaultCurve,
      constraints: const BoxConstraints(minHeight: AppSpacing.xxxl),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.chipBorderRadius),
        border: colors.borderColor == null
            ? null
            : Border.all(color: colors.borderColor!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: AppSpacing.md + AppSpacing.xs / 2,
              color: colors.foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: AppTypography.labelMedium(color: colors.foreground),
          ),
        ],
      ),
    );

    if (variant == AppChipVariant.status || onTap == null) return content;

    return GestureDetector(onTap: onTap, child: content);
  }
}

class _AppChipColors {
  final Color background;
  final Color foreground;
  final Color? borderColor;

  const _AppChipColors({
    required this.background,
    required this.foreground,
    this.borderColor,
  });

  factory _AppChipColors.forState({
    required AppChipVariant variant,
    required bool isSelected,
    required Color? selectedColor,
    required bool dark,
  }) {
    final borderColor = dark ? AppColors.borderDark : AppColors.borderLight;
    final secondaryText = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final surface = dark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return switch (variant) {
      AppChipVariant.filter =>
        isSelected
            ? _AppChipColors(
                background: selectedColor ?? AppColors.primary,
                foreground: Colors.white,
              )
            : _AppChipColors(
                background: Colors.transparent,
                foreground: secondaryText,
                borderColor: borderColor,
              ),
      AppChipVariant.status => _AppChipColors(
        background: selectedColor!,
        foreground: Colors.white,
      ),
      AppChipVariant.tag =>
        isSelected
            ? const _AppChipColors(
                background: AppColors.accent,
                foreground: Colors.black,
              )
            : _AppChipColors(
                background: surface,
                foreground: secondaryText,
                borderColor: borderColor,
              ),
    };
  }
}
