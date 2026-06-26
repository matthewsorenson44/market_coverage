import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

enum LoadingVariant { standard, map, inline }

class LoadingState extends StatelessWidget {
  final String? message;
  final LoadingVariant variant;

  const LoadingState({
    super.key,
    this.message,
    this.variant = LoadingVariant.standard,
  });

  const LoadingState.parcels({super.key})
    : message = 'Finding nearby property...',
      variant = LoadingVariant.map;

  const LoadingState.mission({super.key})
    : message = 'Building your mission...',
      variant = LoadingVariant.standard;

  const LoadingState.marketMap({super.key})
    : message = 'Building market map...',
      variant = LoadingVariant.standard;

  const LoadingState.sync({super.key})
    : message = 'Syncing leads...',
      variant = LoadingVariant.inline;

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      LoadingVariant.standard => _StandardLoading(message: message),
      LoadingVariant.map => _MapLoading(message: message),
      LoadingVariant.inline => _InlineLoading(message: message),
    };
  }
}

class _StandardLoading extends StatelessWidget {
  final String? message;

  const _StandardLoading({required this.message});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator.adaptive(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message!,
              style: AppTypography.bodyMedium(
                color: dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _MapLoading extends StatelessWidget {
  final String? message;

  const _MapLoading({required this.message});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.chipBorderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: AppSpacing.xs, sigmaY: AppSpacing.xs),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: dark
                ? AppColors.mapOverlayDark
                : AppColors.surfaceLight.withValues(
                    alpha: (AppSpacing.massive + AppSpacing.xxl) / 100,
                  ),
            borderRadius: BorderRadius.circular(AppSpacing.chipBorderRadius),
            border: Border.all(
              color: dark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: _InlineLoading(message: message),
        ),
      ),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  final String? message;

  const _InlineLoading({required this.message});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: AppSpacing.lg,
          child: const CircularProgressIndicator.adaptive(
            strokeWidth: AppSpacing.xs / 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        if (message != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              message!,
              style: AppTypography.bodySmall(
                color: dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
