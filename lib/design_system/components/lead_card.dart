import 'package:flutter/material.dart';

import '../../main.dart';
import 'app_badge.dart';
import 'app_card.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

class LeadCard extends StatelessWidget {
  final Lead lead;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showMissionBadge;
  final bool isCompact;

  const LeadCard({
    super.key,
    required this.lead,
    this.onTap,
    this.onLongPress,
    this.showMissionBadge = false,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scoreColor = leadScoreColor(lead.score);
    final primaryLabel = _primaryLabel;
    final address = lead.address.trim();
    final showAddress = address.isNotEmpty && address != primaryLabel;

    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.cardBorderRadius),
        border: Border(
          left: BorderSide(color: scoreColor, width: _accentWidth),
        ),
      ),
      child: AppCard(
        onTap: onTap,
        onLongPress: onLongPress,
        padding: EdgeInsets.all(isCompact ? AppSpacing.sm : AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: AppSpacing.massive - AppSpacing.md,
              child: _ScoreBox(score: lead.score, color: scoreColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          primaryLabel,
                          style: AppTypography.headingSmall(dark: dark),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lead.parcelData.outOfStateOwner) ...[
                        const SizedBox(width: AppSpacing.xs),
                        const AppBadge(
                          label: 'OOS',
                          variant: AppBadgeVariant.custom,
                          customColor: AppColors.accent,
                          size: AppBadgeSize.small,
                        ),
                      ],
                    ],
                  ),
                  if (showAddress) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      address,
                      style: AppTypography.bodySmall(
                        color: dark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      AppBadge(
                        label: normalizeLeadStage(lead.status),
                        variant: AppBadgeVariant.custom,
                        customColor: leadStatusColor(lead.status),
                        size: AppBadgeSize.small,
                      ),
                      if (lead.offerData.mao != null)
                        AppBadge(
                          label: 'MAO: ${formatMoney(lead.offerData.mao)}',
                          variant: AppBadgeVariant.neutral,
                          size: AppBadgeSize.small,
                        ),
                      if (lead.saleData.lastSaleDate.trim().isNotEmpty)
                        AppBadge(
                          label: lead.saleData.lastSaleDate,
                          variant: AppBadgeVariant.neutral,
                          size: AppBadgeSize.small,
                        ),
                    ],
                  ),
                  if (!isCompact) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lead.source,
                            style: AppTypography.labelSmall(
                              color: dark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiaryLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showMissionBadge &&
                            lead.reminderData.reminderDate != null)
                          _DueLabel(
                            label:
                                'Due ${displayDate(lead.reminderData.reminderDate)}',
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _primaryLabel {
    final owner = lead.parcelData.ownerName.trim();
    if (owner.isNotEmpty) return owner;

    final address = lead.address.trim();
    if (address.isNotEmpty) return address;

    return 'Unnamed lead';
  }

  static const double _accentWidth = AppSpacing.xs - AppSpacing.xs / 4;
}

class _ScoreBox extends StatelessWidget {
  final int score;
  final Color color;

  const _ScoreBox({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.touchTarget,
      height: AppSpacing.touchTarget,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(
          AppSpacing.buttonBorderRadius + AppSpacing.xs / 2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$score',
        style: AppTypography.monoLarge(color: AppColors.textPrimaryDark),
      ),
    );
  }
}

class _DueLabel extends StatelessWidget {
  final String label;

  const _DueLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.schedule_rounded,
          size: AppSpacing.lg,
          color: AppColors.accent,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.labelSmall(color: AppColors.accent)),
      ],
    );
  }
}
