import 'package:flutter/material.dart';

import 'app_card.dart';
import 'app_chip.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

class MissionCardData {
  final String id;
  final String areaName;
  final String status;
  final int streetCount;
  final int coveredStreetCount;
  final int? timeBudgetMinutes;
  final int? actualMinutes;
  final double? opportunityAtStart;
  final int leadsFound;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? scheduledDate;

  const MissionCardData({
    required this.id,
    required this.areaName,
    required this.status,
    required this.streetCount,
    required this.coveredStreetCount,
    required this.timeBudgetMinutes,
    required this.actualMinutes,
    required this.opportunityAtStart,
    required this.leadsFound,
    required this.createdAt,
    required this.completedAt,
    required this.scheduledDate,
  });

  factory MissionCardData.fromMap(
    Map<String, dynamic> map, {
    required String areaName,
    required int leadsFound,
    required int coveredStreetCount,
  }) {
    return MissionCardData(
      id: map['id']?.toString() ?? '',
      areaName: areaName,
      status: map['status']?.toString() ?? 'active',
      streetCount: ((map['street_count'] ?? 0) as num).toInt(),
      coveredStreetCount: coveredStreetCount,
      timeBudgetMinutes: map['time_budget_minutes'] == null
          ? null
          : (map['time_budget_minutes'] as num).toInt(),
      actualMinutes: map['actual_minutes'] == null
          ? null
          : (map['actual_minutes'] as num).toInt(),
      opportunityAtStart: map['opportunity_at_start'] == null
          ? null
          : (map['opportunity_at_start'] as num).toDouble(),
      leadsFound: leadsFound,
      createdAt: _parseDate(map['created_at']),
      completedAt: _parseDate(map['completed_at']),
      scheduledDate: _parseDate(map['scheduled_date']),
    );
  }

  double get completionPercent =>
      streetCount == 0 ? 0 : (coveredStreetCount / streetCount).clamp(0.0, 1.0);

  String get statusLabel => switch (status) {
    'active' => 'In Progress',
    'paused' => 'Paused',
    'completed' => 'Completed',
    'scheduled' => 'Scheduled',
    _ => 'Unknown',
  };

  Color get statusColor => switch (status) {
    'active' => AppColors.primary,
    'paused' => AppColors.warning,
    'completed' => AppColors.success,
    'scheduled' => AppColors.textSecondaryDark,
    _ => AppColors.textTertiaryDark,
  };

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

class MissionCard extends StatelessWidget {
  final MissionCardData mission;
  final VoidCallback? onTap;
  final bool showAreaName;

  const MissionCard({
    super.key,
    required this.mission,
    this.onTap,
    this.showAreaName = true,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showAreaName)
                Expanded(
                  child: Text(
                    mission.areaName,
                    style: AppTypography.headingSmall(dark: dark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              AppChip(
                label: mission.statusLabel,
                variant: AppChipVariant.status,
                selectedColor: mission.statusColor,
              ),
            ],
          ),
          if (_showsProgress) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.smallBorderRadius),
              child: LinearProgressIndicator(
                value: mission.completionPercent,
                minHeight: AppSpacing.sm - AppSpacing.xs / 2,
                color: _progressColor,
                backgroundColor: dark
                    ? AppColors.surfaceElevatedDark
                    : AppColors.surfaceElevatedLight,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${mission.coveredStreetCount} of ${mission.streetCount} streets',
              style: AppTypography.bodySmall(
                color: dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _MissionStat(
                  value: '${mission.streetCount}',
                  label: 'Streets',
                ),
              ),
              Expanded(
                child: _MissionStat(
                  value:
                      '${mission.actualMinutes ?? mission.timeBudgetMinutes ?? 0} min',
                  label: 'Time',
                ),
              ),
              Expanded(
                child: _MissionStat(
                  value: '${mission.leadsFound}',
                  label: 'Leads',
                  valueColor: AppColors.accent,
                ),
              ),
            ],
          ),
          if (mission.status == 'completed') ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _completionLabel,
                    style: AppTypography.bodySmall(
                      color: dark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight,
                    ),
                  ),
                ),
                Text(
                  'View Results ->',
                  style: AppTypography.labelSmall(color: AppColors.primary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool get _showsProgress =>
      mission.status == 'active' ||
      mission.status == 'paused' ||
      mission.status == 'completed';

  Color get _progressColor => switch (mission.status) {
    'completed' => AppColors.success,
    'paused' => AppColors.warning,
    _ => AppColors.primary,
  };

  String get _completionLabel {
    final date = mission.completedAt;
    if (date == null) return 'Completed';

    return 'Completed ${date.month}/${date.day}/${date.year}';
  }
}

class _MissionStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const _MissionStat({
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTypography.monoMedium(color: valueColor)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.labelSmall(
            color: dark
                ? AppColors.textTertiaryDark
                : AppColors.textTertiaryLight,
          ),
        ),
      ],
    );
  }
}
