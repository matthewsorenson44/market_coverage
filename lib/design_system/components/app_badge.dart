import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

enum AppBadgeVariant {
  success,
  danger,
  warning,
  info,
  neutral,
  primary,
  custom,
}

enum AppBadgeSize { small, medium, large }

class AppBadge extends StatelessWidget {
  final String label;
  final AppBadgeVariant variant;
  final AppBadgeSize size;
  final Color? customColor;

  const AppBadge({
    super.key,
    required this.label,
    this.variant = AppBadgeVariant.neutral,
    this.size = AppBadgeSize.medium,
    this.customColor,
  });

  const AppBadge.score(int score, {super.key, this.size = AppBadgeSize.medium})
    : label = '$score',
      variant = score >= 70
          ? AppBadgeVariant.danger
          : score >= 40
          ? AppBadgeVariant.warning
          : AppBadgeVariant.success,
      customColor = null;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = _AppBadgeColors.forVariant(
      variant,
      customColor: customColor,
      dark: dark,
    );
    final metrics = _AppBadgeMetrics.forSize(size);

    return Container(
      constraints: BoxConstraints(minHeight: metrics.height),
      padding: EdgeInsets.symmetric(horizontal: metrics.padding),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.chipBorderRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: metrics.textStyle(colors.foreground),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}

class _AppBadgeColors {
  final Color background;
  final Color foreground;

  const _AppBadgeColors({required this.background, required this.foreground});

  factory _AppBadgeColors.forVariant(
    AppBadgeVariant variant, {
    required Color? customColor,
    required bool dark,
  }) {
    final secondaryText = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return switch (variant) {
      AppBadgeVariant.success => const _AppBadgeColors(
        background: AppColors.success,
        foreground: Colors.white,
      ),
      AppBadgeVariant.danger => const _AppBadgeColors(
        background: AppColors.danger,
        foreground: Colors.white,
      ),
      AppBadgeVariant.warning => const _AppBadgeColors(
        background: AppColors.warning,
        foreground: Colors.white,
      ),
      AppBadgeVariant.info => const _AppBadgeColors(
        background: AppColors.primary,
        foreground: Colors.white,
      ),
      AppBadgeVariant.neutral => _AppBadgeColors(
        background: dark
            ? AppColors.surfaceElevatedDark
            : AppColors.surfaceElevatedLight,
        foreground: secondaryText,
      ),
      AppBadgeVariant.primary => const _AppBadgeColors(
        background: AppColors.primary,
        foreground: Colors.white,
      ),
      AppBadgeVariant.custom => _AppBadgeColors(
        background: customColor ?? AppColors.primary,
        foreground: Colors.white,
      ),
    };
  }
}

class _AppBadgeMetrics {
  final double height;
  final double padding;
  final TextStyle Function(Color color) textStyle;

  const _AppBadgeMetrics({
    required this.height,
    required this.padding,
    required this.textStyle,
  });

  factory _AppBadgeMetrics.forSize(AppBadgeSize size) {
    return switch (size) {
      AppBadgeSize.small => _AppBadgeMetrics(
        height: AppSpacing.xl,
        padding: AppSpacing.md / 2,
        textStyle: (color) => AppTypography.labelSmall(color: color),
      ),
      AppBadgeSize.medium => _AppBadgeMetrics(
        height: AppSpacing.xxl,
        padding: AppSpacing.sm,
        textStyle: (color) => AppTypography.labelMedium(color: color),
      ),
      AppBadgeSize.large => _AppBadgeMetrics(
        height: AppSpacing.xxl + AppSpacing.xs,
        padding: AppSpacing.xl / 2,
        textStyle: (color) => AppTypography.labelLarge(color: color),
      ),
    };
  }
}
