import 'package:flutter/material.dart';

import 'app_button.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

class ErrorState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? technicalDetail;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const ErrorState({
    super.key,
    required this.title,
    this.subtitle,
    this.technicalDetail,
    this.onRetry,
    this.onDismiss,
  });

  const ErrorState.parcelLookup({super.key, this.onRetry})
    : title = 'Property not found',
      subtitle =
          "Couldn't load parcel data. Check your connection and try again.",
      technicalDetail = null,
      onDismiss = null;

  const ErrorState.missionFailed({super.key, this.onRetry})
    : title = 'Mission failed to start',
      subtitle = 'Something went wrong building your mission.',
      technicalDetail = null,
      onDismiss = null;

  const ErrorState.syncFailed({super.key, this.onRetry})
    : title = 'Sync failed',
      subtitle = 'Your leads are saved locally and will sync when reconnected.',
      technicalDetail = null,
      onDismiss = null;

  const ErrorState.networkError({super.key, this.onRetry})
    : title = 'No connection',
      subtitle = 'Check your internet connection and try again.',
      technicalDetail = null,
      onDismiss = null;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: AppSpacing.massive,
              color: AppColors.danger.withValues(
                alpha: AppSpacing.bottomSheetHandleWidth / 100,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: AppTypography.headingMedium(dark: dark),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                style: AppTypography.bodyMedium(
                  color: dark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (technicalDetail != null) ...[
              const SizedBox(height: AppSpacing.md),
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor:
                      (dark ? AppColors.borderDark : AppColors.borderLight)
                          .withValues(alpha: 0),
                ),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    'Show details',
                    style: AppTypography.labelMedium(color: AppColors.primary),
                    textAlign: TextAlign.center,
                  ),
                  children: [
                    Text(
                      technicalDetail!,
                      style: AppTypography.monoMedium(
                        color: dark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Try Again',
                onPressed: onRetry,
                leadingIcon: Icons.refresh_rounded,
              ),
            ],
            if (onDismiss != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Dismiss',
                onPressed: onDismiss,
                variant: AppButtonVariant.ghost,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
