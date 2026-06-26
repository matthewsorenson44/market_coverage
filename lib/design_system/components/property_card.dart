import 'package:flutter/material.dart';

import '../../main.dart';
import 'app_badge.dart';
import 'app_button.dart';
import 'app_card.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

enum PropertyCardVariant { preview, target, compact }

class PropertyCard extends StatelessWidget {
  final ParcelProperty property;
  final VoidCallback? onAddLead;
  final VoidCallback? onDismiss;
  final bool isAlreadyLead;
  final String? existingLeadStatus;
  final int? targetScore;
  final PropertyCardVariant variant;

  const PropertyCard({
    super.key,
    required this.property,
    this.onAddLead,
    this.onDismiss,
    this.isAlreadyLead = false,
    this.existingLeadStatus,
    this.targetScore,
    this.variant = PropertyCardVariant.preview,
  });

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      PropertyCardVariant.preview => _PreviewPropertyCard(
        property: property,
        onAddLead: onAddLead,
        onDismiss: onDismiss,
        isAlreadyLead: isAlreadyLead,
        existingLeadStatus: existingLeadStatus,
        targetScore: targetScore,
      ),
      PropertyCardVariant.target => _TargetPropertyCard(
        property: property,
        onTap: onAddLead,
        targetScore: targetScore,
      ),
      PropertyCardVariant.compact => _CompactPropertyCard(
        property: property,
        onTap: onAddLead,
        targetScore: targetScore,
      ),
    };
  }
}

class _PreviewPropertyCard extends StatelessWidget {
  final ParcelProperty property;
  final VoidCallback? onAddLead;
  final VoidCallback? onDismiss;
  final bool isAlreadyLead;
  final String? existingLeadStatus;
  final int? targetScore;

  const _PreviewPropertyCard({
    required this.property,
    required this.onAddLead,
    required this.onDismiss,
    required this.isAlreadyLead,
    required this.existingLeadStatus,
    required this.targetScore,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final details = _detailCells(property).take(_maxDetailCells).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  property.displayAddress,
                  style: AppTypography.headingMedium(dark: dark),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (targetScore != null) ...[
                const SizedBox(width: AppSpacing.sm),
                AppBadge.score(targetScore!),
              ],
            ],
          ),
          if (property.outOfStateOwner) ...[
            const SizedBox(height: AppSpacing.sm),
            const AppBadge(
              label: 'OOS',
              variant: AppBadgeVariant.custom,
              customColor: AppColors.accent,
              size: AppBadgeSize.small,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            _clean(property.ownerName, fallback: 'Owner not set'),
            style: AppTypography.bodyMedium(dark: dark),
          ),
          if (_hasText(property.mailingAddress)) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              property.mailingAddress!,
              style: AppTypography.bodySmall(
                color: dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _DetailGrid(details: details),
          ],
          if (_hasText(property.saleDate) || property.salePrice != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(color: dark ? AppColors.borderDark : AppColors.borderLight),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Last Sale',
              style: AppTypography.labelSmall(
                color: dark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _clean(property.saleDate, fallback: 'Date not set'),
                    style: AppTypography.bodySmall(dark: dark),
                  ),
                ),
                Text(
                  formatMoney(property.salePrice),
                  style: AppTypography.bodySmall(dark: dark),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: isAlreadyLead ? 'View Lead' : 'Add Lead',
            onPressed: onAddLead,
            variant: isAlreadyLead
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            leadingIcon: isAlreadyLead
                ? Icons.arrow_forward_rounded
                : Icons.add_rounded,
            fullWidth: true,
          ),
          if (isAlreadyLead && _hasText(existingLeadStatus)) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              existingLeadStatus!,
              style: AppTypography.labelSmall(
                color: dark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ),
          ],
          if (onDismiss != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Dismiss',
              onPressed: onDismiss,
              variant: AppButtonVariant.ghost,
              fullWidth: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _TargetPropertyCard extends StatelessWidget {
  final ParcelProperty property;
  final VoidCallback? onTap;
  final int? targetScore;

  const _TargetPropertyCard({
    required this.property,
    required this.onTap,
    required this.targetScore,
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
              Expanded(
                child: Text(
                  property.displayAddress,
                  style: AppTypography.headingSmall(dark: dark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (property.outOfStateOwner)
                const AppBadge(
                  label: 'OOS',
                  variant: AppBadgeVariant.custom,
                  customColor: AppColors.accent,
                  size: AppBadgeSize.small,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _clean(property.ownerName, fallback: 'Owner not set'),
            style: AppTypography.bodySmall(
              color: dark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (targetScore != null) AppBadge.score(targetScore!),
              AppBadge(
                label: formatMoney(property.assessedValue),
                variant: AppBadgeVariant.neutral,
                size: AppBadgeSize.small,
              ),
              AppBadge(
                label: _signalLabel(property),
                variant: AppBadgeVariant.neutral,
                size: AppBadgeSize.small,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactPropertyCard extends StatelessWidget {
  final ParcelProperty property;
  final VoidCallback? onTap;
  final int? targetScore;

  const _CompactPropertyCard({
    required this.property,
    required this.onTap,
    required this.targetScore,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          if (targetScore != null) ...[
            AppBadge.score(targetScore!),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.displayAddress,
                  style: AppTypography.labelLarge(dark: dark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _clean(property.ownerName, fallback: 'Owner not set'),
                  style: AppTypography.bodySmall(
                    color: dark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: dark
                ? AppColors.textTertiaryDark
                : AppColors.textTertiaryLight,
          ),
        ],
      ),
    );
  }
}

class _DetailGrid extends StatelessWidget {
  final List<_PropertyDetail> details;

  const _DetailGrid({required this.details});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < details.length; index += 2) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _DetailCell(detail: details[index])),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: index + 1 < details.length
                  ? _DetailCell(detail: details[index + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (index + 2 < details.length) {
        rows.add(const SizedBox(height: AppSpacing.md));
      }
    }

    return Column(children: rows);
  }
}

class _DetailCell extends StatelessWidget {
  final _PropertyDetail detail;

  const _DetailCell({required this.detail});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.label,
          style: AppTypography.labelSmall(
            color: dark
                ? AppColors.textTertiaryDark
                : AppColors.textTertiaryLight,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          detail.value,
          style: AppTypography.bodySmall(dark: dark),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _PropertyDetail {
  final String label;
  final String value;

  const _PropertyDetail(this.label, this.value);
}

List<_PropertyDetail> _detailCells(ParcelProperty property) {
  final cells = <_PropertyDetail>[
    if (property.yearBuilt != null)
      _PropertyDetail('Year Built', property.yearBuilt.toString()),
    if (property.squareFeet != null)
      _PropertyDetail('Sq Ft', formatDecimal(property.squareFeet)),
    if (_hasText(property.lotSizeDisplay))
      _PropertyDetail('Lot', property.lotSizeDisplay),
    if (property.assessedValue != null)
      _PropertyDetail('Assessed', formatMoney(property.assessedValue)),
    if (property.landValue != null)
      _PropertyDetail('Land Value', formatMoney(property.landValue)),
    if (property.improvementValue != null)
      _PropertyDetail('Imp Value', formatMoney(property.improvementValue)),
    if (property.bathrooms != null)
      _PropertyDetail('Baths', formatDecimal(property.bathrooms)),
    if (property.stories != null)
      _PropertyDetail('Stories', formatDecimal(property.stories)),
  ];

  return cells;
}

String _signalLabel(ParcelProperty property) {
  if (property.outOfStateOwner) return 'Out of state';
  if (property.yearBuilt != null) return 'Built ${property.yearBuilt}';
  if (_hasText(property.propertyType)) return property.propertyType!;
  return 'Target';
}

String _clean(String? value, {required String fallback}) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed;
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

const int _maxDetailCells = 8;
