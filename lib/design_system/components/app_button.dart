import 'package:flutter/material.dart';

import '../tokens/app_animations.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

enum AppButtonVariant { primary, secondary, ghost, danger, accent }

enum AppButtonSize { small, medium, large }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool fullWidth;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = _AppButtonColors.forVariant(variant, dark: dark);
    final disabled = onPressed == null || isLoading;
    final metrics = _AppButtonMetrics.forSize(size);

    return AnimatedOpacity(
      duration: AppAnimations.microDuration,
      curve: AppAnimations.defaultCurve,
      opacity: onPressed == null
          ? (AppSpacing.touchTarget - AppSpacing.sm) / 100
          : 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: fullWidth ? double.infinity : 0,
          minHeight: AppSpacing.touchTarget,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: disabled ? null : onPressed,
            borderRadius: BorderRadius.circular(AppSpacing.buttonBorderRadius),
            child: Ink(
              width: fullWidth ? double.infinity : null,
              height: metrics.height,
              padding: EdgeInsets.symmetric(horizontal: metrics.padding),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(
                  AppSpacing.buttonBorderRadius,
                ),
                border: colors.borderColor == null
                    ? null
                    : Border.all(color: colors.borderColor!),
              ),
              child: Center(
                widthFactor: fullWidth ? null : 1,
                child: isLoading
                    ? SizedBox.square(
                        dimension: AppSpacing.lg + AppSpacing.xs / 2,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: AppSpacing.xs / 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors.foreground,
                          ),
                        ),
                      )
                    : _AppButtonContent(
                        label: label,
                        leadingIcon: leadingIcon,
                        trailingIcon: trailingIcon,
                        iconSize: metrics.iconSize,
                        style: metrics.textStyle(colors.foreground),
                        foreground: colors.foreground,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppButtonContent extends StatelessWidget {
  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final double iconSize;
  final TextStyle style;
  final Color foreground;

  const _AppButtonContent({
    required this.label,
    required this.leadingIcon,
    required this.trailingIcon,
    required this.iconSize,
    required this.style,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: iconSize, color: foreground),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            label,
            style: style,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Icon(trailingIcon, size: iconSize, color: foreground),
        ],
      ],
    );
  }
}

class _AppButtonColors {
  final Color background;
  final Color foreground;
  final Color? borderColor;

  const _AppButtonColors({
    required this.background,
    required this.foreground,
    this.borderColor,
  });

  factory _AppButtonColors.forVariant(
    AppButtonVariant variant, {
    required bool dark,
  }) {
    return switch (variant) {
      AppButtonVariant.primary => const _AppButtonColors(
        background: AppColors.primary,
        foreground: Colors.white,
      ),
      AppButtonVariant.secondary => _AppButtonColors(
        background: Colors.transparent,
        foreground: AppColors.primary,
        borderColor: AppColors.primary.withValues(
          alpha: (AppSpacing.huge + AppSpacing.md) / 100,
        ),
      ),
      AppButtonVariant.ghost => _AppButtonColors(
        background: Colors.transparent,
        foreground: dark
            ? AppColors.textPrimaryDark
            : AppColors.textPrimaryLight,
      ),
      AppButtonVariant.danger => const _AppButtonColors(
        background: AppColors.danger,
        foreground: Colors.white,
      ),
      AppButtonVariant.accent => const _AppButtonColors(
        background: AppColors.accent,
        foreground: Colors.black,
      ),
    };
  }
}

class _AppButtonMetrics {
  final double height;
  final double padding;
  final double iconSize;
  final TextStyle Function(Color color) textStyle;

  const _AppButtonMetrics({
    required this.height,
    required this.padding,
    required this.iconSize,
    required this.textStyle,
  });

  factory _AppButtonMetrics.forSize(AppButtonSize size) {
    return switch (size) {
      AppButtonSize.small => _AppButtonMetrics(
        height: AppSpacing.touchTarget,
        padding: AppSpacing.md,
        iconSize: AppSpacing.lg + AppSpacing.xs / 2,
        textStyle: (color) => AppTypography.labelMedium(color: color),
      ),
      AppButtonSize.medium => _AppButtonMetrics(
        height: AppSpacing.touchTarget,
        padding: AppSpacing.lg,
        iconSize: AppSpacing.xl,
        textStyle: (color) => AppTypography.labelLarge(color: color),
      ),
      AppButtonSize.large => _AppButtonMetrics(
        height: AppSpacing.fabSize,
        padding: AppSpacing.xl,
        iconSize: AppSpacing.xl + AppSpacing.xs / 2,
        textStyle: (color) => AppTypography.headingSmall(color: color),
      ),
    };
  }
}
