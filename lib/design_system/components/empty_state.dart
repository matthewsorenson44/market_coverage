import 'package:flutter/material.dart';

import 'app_button.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

enum EmptyStateVariant { standard, search, error, offline }

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final AppButton? action;
  final EmptyStateVariant variant;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.variant = EmptyStateVariant.standard,
  });

  factory EmptyState.noLeads({VoidCallback? onStartDriving}) {
    return EmptyState(
      icon: Icons.location_off_outlined,
      title: 'No leads yet',
      subtitle: 'Start a mission to begin capturing properties',
      action: onStartDriving == null
          ? null
          : AppButton(
              label: 'Start Driving',
              onPressed: onStartDriving,
              leadingIcon: Icons.directions_car_rounded,
            ),
    );
  }

  factory EmptyState.noMissions({VoidCallback? onPlan}) {
    return EmptyState(
      icon: Icons.flag_outlined,
      title: 'No missions yet',
      subtitle: "Plan today's drive to create your first mission",
      action: onPlan == null
          ? null
          : AppButton(
              label: 'Plan Drive',
              onPressed: onPlan,
              leadingIcon: Icons.event_rounded,
            ),
    );
  }

  factory EmptyState.noStreetData({VoidCallback? onGoToAreas}) {
    return EmptyState(
      icon: Icons.map_outlined,
      title: 'No street data',
      subtitle: 'Import street data for this market to unlock missions',
      action: onGoToAreas == null
          ? null
          : AppButton(
              label: 'Go to Markets',
              onPressed: onGoToAreas,
              leadingIcon: Icons.map_rounded,
            ),
    );
  }

  factory EmptyState.searchEmpty({required String query}) {
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'No results for "$query"',
      subtitle: 'Try a different address, owner name, or note',
      variant: EmptyStateVariant.search,
    );
  }

  factory EmptyState.offline() {
    return const EmptyState(
      icon: Icons.wifi_off_rounded,
      title: "You're offline",
      subtitle: 'Leads saved locally will sync when you reconnect',
      variant: EmptyStateVariant.offline,
    );
  }

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
              icon,
              size: AppSpacing.massive,
              color:
                  (dark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight)
                      .withValues(
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
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
