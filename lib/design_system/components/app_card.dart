import 'package:flutter/material.dart';

import '../tokens/app_animations.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_shadows.dart';
import '../tokens/app_spacing.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final bool showBorder;
  final bool isSelected;
  final double? borderRadius;
  final bool _elevated;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.backgroundColor,
    this.showBorder = false,
    this.isSelected = false,
    this.borderRadius,
  }) : _elevated = false;

  const AppCard.elevated({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.backgroundColor,
    this.showBorder = false,
    this.isSelected = false,
    this.borderRadius,
  }) : _elevated = true;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? AppSpacing.cardBorderRadius;
    final baseColor =
        backgroundColor ??
        (_elevated
            ? (dark
                  ? AppColors.surfaceElevatedDark
                  : AppColors.surfaceElevatedLight)
            : (dark ? AppColors.surfaceDark : AppColors.surfaceLight));
    final selectedColor = Color.alphaBlend(
      AppColors.primary.withValues(alpha: AppSpacing.sm / 100),
      baseColor,
    );
    final borderColor = isSelected
        ? AppColors.primary
        : (dark ? AppColors.borderDark : AppColors.borderLight);
    final borderWidth = isSelected ? AppSpacing.xs / 2 : AppSpacing.xs / 4;
    final shadows = _elevated
        ? AppShadows.elevated
        : (dark ? AppShadows.cardDark : AppShadows.card);

    final content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      child: child,
    );

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? selectedColor : baseColor,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows,
        border: showBorder || isSelected
            ? Border.all(color: borderColor, width: borderWidth)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: onTap == null && onLongPress == null
            ? content
            : InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(radius),
                hoverDuration: AppAnimations.fastDuration,
                child: content,
              ),
      ),
    );
  }
}
