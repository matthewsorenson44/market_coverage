import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../main.dart';
import 'components/app_badge.dart';
import 'components/app_button.dart';
import 'components/app_card.dart';
import 'components/app_chip.dart';
import 'components/app_text_field.dart';
import 'components/empty_state.dart';
import 'components/error_state.dart';
import 'components/lead_card.dart';
import 'components/loading_state.dart';
import 'components/mission_card.dart';
import 'components/property_card.dart';
import 'tokens/app_animations.dart';
import 'tokens/app_colors.dart';
import 'tokens/app_shadows.dart';
import 'tokens/app_spacing.dart';
import 'tokens/app_typography.dart';

class DesignSystemGallery extends StatelessWidget {
  static const String route = '/debug/design-system';

  const DesignSystemGallery({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Design System')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _Section(
            title: 'Colors',
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: _colorTokens
                  .map((token) => _ColorSwatch(token: token))
                  .toList(),
            ),
          ),
          _Section(
            title: 'Typography',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TypeSample(
                  label: 'displayLarge',
                  style: AppTypography.displayLarge(dark: dark),
                ),
                _TypeSample(
                  label: 'displayMedium',
                  style: AppTypography.displayMedium(dark: dark),
                ),
                _TypeSample(
                  label: 'headingLarge',
                  style: AppTypography.headingLarge(dark: dark),
                ),
                _TypeSample(
                  label: 'headingMedium',
                  style: AppTypography.headingMedium(dark: dark),
                ),
                _TypeSample(
                  label: 'headingSmall',
                  style: AppTypography.headingSmall(dark: dark),
                ),
                _TypeSample(
                  label: 'bodyLarge',
                  style: AppTypography.bodyLarge(dark: dark),
                ),
                _TypeSample(
                  label: 'bodyMedium',
                  style: AppTypography.bodyMedium(dark: dark),
                ),
                _TypeSample(
                  label: 'bodySmall',
                  style: AppTypography.bodySmall(dark: dark),
                ),
                _TypeSample(
                  label: 'labelLarge',
                  style: AppTypography.labelLarge(dark: dark),
                ),
                _TypeSample(
                  label: 'labelMedium',
                  style: AppTypography.labelMedium(dark: dark),
                ),
                _TypeSample(
                  label: 'labelSmall',
                  style: AppTypography.labelSmall(dark: dark),
                ),
                _TypeSample(
                  label: 'monoLarge',
                  style: AppTypography.monoLarge(dark: dark),
                ),
                _TypeSample(
                  label: 'monoMedium',
                  style: AppTypography.monoMedium(dark: dark),
                ),
                _TypeSample(
                  label: 'hudDisplay',
                  style: AppTypography.hudDisplay(dark: dark),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Spacing',
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: _spacingTokens
                  .map((token) => _SpacingBox(token: token))
                  .toList(),
            ),
          ),
          _Section(
            title: 'Shadows',
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: _shadowTokens
                  .map((token) => _ShadowSample(token: token))
                  .toList(),
            ),
          ),
          _Section(
            title: 'Animations',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _animationTokens
                  .map(
                    (token) =>
                        _TokenLine(label: token.name, value: token.value),
                  )
                  .toList(),
            ),
          ),
          const _PrimitiveComponentsSection(),
          const _DomainComponentsSection(),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.displayMedium(dark: dark)),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final _ColorToken token;

  const _ColorSwatch({required this.token});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 64,
            decoration: BoxDecoration(
              color: token.color,
              borderRadius: BorderRadius.circular(
                AppSpacing.buttonBorderRadius,
              ),
              border: Border.all(
                color: dark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(token.name, style: AppTypography.labelMedium(dark: dark)),
          Text(token.value, style: AppTypography.monoMedium(dark: dark)),
        ],
      ),
    );
  }
}

class _TypeSample extends StatelessWidget {
  final String label;
  final TextStyle style;

  const _TypeSample({required this.label, required this.style});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.labelMedium(dark: dark)),
          Text('Market Coverage OS', style: style),
        ],
      ),
    );
  }
}

class _SpacingBox extends StatelessWidget {
  final _NumberToken token;

  const _SpacingBox({required this.token});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = token.value.clamp(4, 72).toDouble();

    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppSpacing.smallBorderRadius),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(token.name, style: AppTypography.labelMedium(dark: dark)),
          Text('${token.value}px', style: AppTypography.monoMedium(dark: dark)),
        ],
      ),
    );
  }
}

class _ShadowSample extends StatelessWidget {
  final _ShadowToken token;

  const _ShadowSample({required this.token});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 156,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardBorderRadius),
        boxShadow: token.shadows,
        border: Border.all(
          color: dark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(token.name, style: AppTypography.labelMedium(dark: dark)),
          const SizedBox(height: AppSpacing.sm),
          Text(token.value, style: AppTypography.bodySmall(dark: dark)),
        ],
      ),
    );
  }
}

class _TokenLine extends StatelessWidget {
  final String label;
  final String value;

  const _TokenLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTypography.labelLarge(dark: dark)),
          ),
          Text(value, style: AppTypography.monoMedium(dark: dark)),
        ],
      ),
    );
  }
}

class _PrimitiveComponentsSection extends StatelessWidget {
  const _PrimitiveComponentsSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Primitive Components',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _GalleryGroup(title: 'AppButton', child: _ButtonSamples()),
          SizedBox(height: AppSpacing.xxl),
          _GalleryGroup(title: 'AppCard', child: _CardSamples()),
          SizedBox(height: AppSpacing.xxl),
          _GalleryGroup(title: 'AppChip', child: _ChipSamples()),
          SizedBox(height: AppSpacing.xxl),
          _GalleryGroup(title: 'AppTextField', child: _TextFieldSamples()),
          SizedBox(height: AppSpacing.xxl),
          _GalleryGroup(title: 'AppBadge', child: _BadgeSamples()),
        ],
      ),
    );
  }
}

class _GalleryGroup extends StatelessWidget {
  final String title;
  final Widget child;

  const _GalleryGroup({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.headingMedium(dark: dark)),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}

class _ButtonSamples extends StatelessWidget {
  const _ButtonSamples();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        AppButton(
          label: 'Start Mission',
          onPressed: () {},
          leadingIcon: Icons.flag,
        ),
        AppButton(
          label: 'Open Area',
          onPressed: () {},
          variant: AppButtonVariant.secondary,
          leadingIcon: Icons.open_in_new,
        ),
        AppButton(
          label: 'Skip Street',
          onPressed: () {},
          variant: AppButtonVariant.ghost,
        ),
        AppButton(
          label: 'Delete Area',
          onPressed: () {},
          variant: AppButtonVariant.danger,
          leadingIcon: Icons.delete_outline,
        ),
        AppButton(
          label: 'Quick Capture',
          onPressed: () {},
          variant: AppButtonVariant.accent,
          leadingIcon: Icons.flash_on,
        ),
        AppButton(
          label: 'Add Lead',
          onPressed: () {},
          size: AppButtonSize.small,
          leadingIcon: Icons.add_location_alt,
        ),
        AppButton(
          label: 'Find Motivated Sellers',
          onPressed: () {},
          size: AppButtonSize.large,
          trailingIcon: Icons.arrow_forward,
        ),
        AppButton(label: 'Saving Mission', onPressed: () {}, isLoading: true),
        const AppButton(
          label: 'No Streets Ready',
          onPressed: null,
          variant: AppButtonVariant.secondary,
        ),
      ],
    );
  }
}

class _CardSamples extends StatelessWidget {
  const _CardSamples();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        SizedBox(
          width: AppSpacing.massive * 3,
          child: AppCard(
            showBorder: true,
            child: _CardText(
              title: 'North Owasso',
              body: '81 streets remaining',
              dark: dark,
            ),
          ),
        ),
        SizedBox(
          width: AppSpacing.massive * 3,
          child: AppCard(
            onTap: () {},
            isSelected: true,
            child: _CardText(
              title: 'Active Mission',
              body: '30 streets queued',
              dark: dark,
            ),
          ),
        ),
        SizedBox(
          width: AppSpacing.massive * 3,
          child: AppCard.elevated(
            child: _CardText(
              title: 'Mission Recap',
              body: '12 leads captured',
              dark: dark,
            ),
          ),
        ),
      ],
    );
  }
}

class _CardText extends StatelessWidget {
  final String title;
  final String body;
  final bool dark;

  const _CardText({
    required this.title,
    required this.body,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.headingSmall(dark: dark)),
        const SizedBox(height: AppSpacing.sm),
        Text(body, style: AppTypography.bodySmall(dark: dark)),
      ],
    );
  }
}

class _ChipSamples extends StatelessWidget {
  const _ChipSamples();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        AppChip(label: 'Open Streets', onTap: () {}, icon: Icons.route),
        AppChip(
          label: 'Covered',
          isSelected: true,
          onTap: () {},
          icon: Icons.check,
        ),
        const AppChip(
          label: 'Contact Needed',
          variant: AppChipVariant.status,
          selectedColor: AppColors.warning,
        ),
        AppChip(label: 'Tall Grass', variant: AppChipVariant.tag, onTap: () {}),
        AppChip(
          label: 'Vacant',
          variant: AppChipVariant.tag,
          isSelected: true,
          onTap: () {},
          icon: Icons.home_work_outlined,
        ),
      ],
    );
  }
}

class _TextFieldSamples extends StatefulWidget {
  const _TextFieldSamples();

  @override
  State<_TextFieldSamples> createState() => _TextFieldSamplesState();
}

class _TextFieldSamplesState extends State<_TextFieldSamples> {
  final TextEditingController _areaController = TextEditingController(
    text: 'North Owasso',
  );

  @override
  void dispose() {
    _areaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppTextField(
          label: 'Area name',
          hint: 'North Owasso',
          leadingIcon: Icons.map_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        const AppTextField(
          label: 'Owner phone',
          hint: 'Add phone number',
          keyboardType: TextInputType.phone,
          errorText: 'Phone number is required before callback.',
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _areaController,
          label: 'Mission search',
          hint: 'Search streets',
          showClearButton: true,
          leadingIcon: Icons.search,
        ),
        const SizedBox(height: AppSpacing.md),
        const AppTextField(
          label: 'Parcel ID',
          hint: 'Auto-filled from county data',
          readOnly: true,
          trailingIcon: Icons.lock_outline,
        ),
      ],
    );
  }
}

class _BadgeSamples extends StatelessWidget {
  const _BadgeSamples();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: const [
        AppBadge(
          label: 'Ready',
          variant: AppBadgeVariant.success,
          size: AppBadgeSize.small,
        ),
        AppBadge(label: 'Dead Lead', variant: AppBadgeVariant.danger),
        AppBadge(label: 'Needs Revisit', variant: AppBadgeVariant.warning),
        AppBadge(label: 'Route Active', variant: AppBadgeVariant.info),
        AppBadge(label: 'Planned', variant: AppBadgeVariant.neutral),
        AppBadge(
          label: 'Active Market',
          variant: AppBadgeVariant.primary,
          size: AppBadgeSize.large,
        ),
        AppBadge(
          label: 'Driving For Dollars',
          variant: AppBadgeVariant.custom,
          customColor: AppColors.accent,
        ),
        AppBadge.score(20),
        AppBadge.score(55),
        AppBadge.score(80),
      ],
    );
  }
}

class _DomainComponentsSection extends StatelessWidget {
  const _DomainComponentsSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Domain Components',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GalleryGroup(
            title: 'LeadCard',
            child: Column(
              children: [
                LeadCard(
                  lead: _galleryLead,
                  showMissionBadge: true,
                  onTap: () {},
                  onLongPress: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                LeadCard(lead: _galleryLead, isCompact: true, onTap: () {}),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _GalleryGroup(
            title: 'MissionCard',
            child: Column(
              children: [
                MissionCard(mission: _activeMission, onTap: () {}),
                const SizedBox(height: AppSpacing.md),
                MissionCard(mission: _completedMission, onTap: () {}),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _GalleryGroup(
            title: 'PropertyCard',
            child: Column(
              children: [
                PropertyCard(
                  property: _galleryProperty,
                  targetScore: _galleryProperty.targetScore?.round(),
                  onAddLead: () {},
                  onDismiss: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                PropertyCard(
                  property: _galleryProperty,
                  targetScore: _galleryProperty.targetScore?.round(),
                  variant: PropertyCardVariant.target,
                  onAddLead: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                PropertyCard(
                  property: _galleryProperty,
                  targetScore: _galleryProperty.targetScore?.round(),
                  variant: PropertyCardVariant.compact,
                  onAddLead: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _GalleryGroup(
            title: 'EmptyState',
            child: Column(
              children: [
                EmptyState.noLeads(),
                const SizedBox(height: AppSpacing.md),
                EmptyState.searchEmpty(query: 'vacant house on maple'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          const _GalleryGroup(
            title: 'LoadingState',
            child: Column(
              children: [
                LoadingState.parcels(),
                SizedBox(height: AppSpacing.md),
                LoadingState(message: 'Loading market coverage...'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _GalleryGroup(
            title: 'ErrorState',
            child: Column(
              children: [
                ErrorState.parcelLookup(onRetry: () {}),
                const SizedBox(height: AppSpacing.md),
                const ErrorState.syncFailed(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorToken {
  final String name;
  final Color color;
  final String value;

  const _ColorToken(this.name, this.color, this.value);
}

class _NumberToken {
  final String name;
  final double value;

  const _NumberToken(this.name, this.value);
}

class _ShadowToken {
  final String name;
  final List<BoxShadow> shadows;
  final String value;

  const _ShadowToken(this.name, this.shadows, this.value);
}

class _TextToken {
  final String name;
  final String value;

  const _TextToken(this.name, this.value);
}

const List<_ColorToken> _colorTokens = [
  _ColorToken('primary', AppColors.primary, '#1B6FEB'),
  _ColorToken('primaryDark', AppColors.primaryDark, '#0F4DB8'),
  _ColorToken('primaryLight', AppColors.primaryLight, '#60A5FA'),
  _ColorToken('accent', AppColors.accent, '#F59E0B'),
  _ColorToken('accentDark', AppColors.accentDark, '#B45309'),
  _ColorToken('success', AppColors.success, '#22C55E'),
  _ColorToken('successSurface', AppColors.successSurface, '#1A22C55E'),
  _ColorToken('danger', AppColors.danger, '#EF4444'),
  _ColorToken('dangerSurface', AppColors.dangerSurface, '#1AEF4444'),
  _ColorToken('warning', AppColors.warning, '#F97316'),
  _ColorToken('warningSurface', AppColors.warningSurface, '#1AF97316'),
  _ColorToken('bgDark', AppColors.bgDark, '#0F1117'),
  _ColorToken('bgLight', AppColors.bgLight, '#F8FAFC'),
  _ColorToken('surfaceDark', AppColors.surfaceDark, '#1C2333'),
  _ColorToken('surfaceLight', AppColors.surfaceLight, '#FFFFFF'),
  _ColorToken('surfaceElevatedDark', AppColors.surfaceElevatedDark, '#263044'),
  _ColorToken(
    'surfaceElevatedLight',
    AppColors.surfaceElevatedLight,
    '#F1F5F9',
  ),
  _ColorToken('borderDark', AppColors.borderDark, '#26FFFFFF'),
  _ColorToken('borderLight', AppColors.borderLight, '#26000000'),
  _ColorToken('textPrimaryDark', AppColors.textPrimaryDark, '#F8FAFC'),
  _ColorToken('textPrimaryLight', AppColors.textPrimaryLight, '#111827'),
  _ColorToken('textSecondaryDark', AppColors.textSecondaryDark, '#CBD5E1'),
  _ColorToken('textSecondaryLight', AppColors.textSecondaryLight, '#4B5563'),
  _ColorToken('textTertiaryDark', AppColors.textTertiaryDark, '#94A3B8'),
  _ColorToken('textTertiaryLight', AppColors.textTertiaryLight, '#6B7280'),
  _ColorToken('mapOverlayDark', AppColors.mapOverlayDark, '#D90F1117'),
  _ColorToken('coverageRed', AppColors.coverageRed, '#66E53935'),
  _ColorToken('coverageGreen', AppColors.coverageGreen, '#CC2E7D32'),
  _ColorToken('coverageBlue', AppColors.coverageBlue, '#FF2196F3'),
  _ColorToken('coverageGrey', AppColors.coverageGrey, '#665F6368'),
];

const List<_NumberToken> _spacingTokens = [
  _NumberToken('xs', AppSpacing.xs),
  _NumberToken('sm', AppSpacing.sm),
  _NumberToken('md', AppSpacing.md),
  _NumberToken('lg', AppSpacing.lg),
  _NumberToken('xl', AppSpacing.xl),
  _NumberToken('xxl', AppSpacing.xxl),
  _NumberToken('xxxl', AppSpacing.xxxl),
  _NumberToken('huge', AppSpacing.huge),
  _NumberToken('massive', AppSpacing.massive),
  _NumberToken('touchTarget', AppSpacing.touchTarget),
  _NumberToken('mapControlSize', AppSpacing.mapControlSize),
  _NumberToken('bottomSheetHandleWidth', AppSpacing.bottomSheetHandleWidth),
  _NumberToken('bottomSheetHandleHeight', AppSpacing.bottomSheetHandleHeight),
  _NumberToken('fabSize', AppSpacing.fabSize),
  _NumberToken('cardBorderRadius', AppSpacing.cardBorderRadius),
  _NumberToken('buttonBorderRadius', AppSpacing.buttonBorderRadius),
  _NumberToken('chipBorderRadius', AppSpacing.chipBorderRadius),
  _NumberToken('smallBorderRadius', AppSpacing.smallBorderRadius),
  _NumberToken('bottomNavHeight', AppSpacing.bottomNavHeight),
  _NumberToken('safeAreaBottomPadding', AppSpacing.safeAreaBottomPadding),
];

const List<_ShadowToken> _shadowTokens = [
  _ShadowToken('none', AppShadows.none, '[]'),
  _ShadowToken('subtle', AppShadows.subtle, '2px blur'),
  _ShadowToken('subtleDark', AppShadows.subtleDark, '2px blur dark'),
  _ShadowToken('card', AppShadows.card, '8px blur, 1px spread'),
  _ShadowToken('cardDark', AppShadows.cardDark, '8px blur dark'),
  _ShadowToken('elevated', AppShadows.elevated, '16px blur, 4px spread'),
  _ShadowToken('elevatedDark', AppShadows.elevatedDark, '16px blur dark'),
  _ShadowToken('mapControl', AppShadows.mapControl, '12px blue-tint blur'),
  _ShadowToken(
    'mapControlDark',
    AppShadows.mapControlDark,
    '12px dark blue-tint blur',
  ),
];

final List<_TextToken> _animationTokens = [
  _TextToken(
    'microDuration',
    '${AppAnimations.microDuration.inMilliseconds}ms',
  ),
  _TextToken('fastDuration', '${AppAnimations.fastDuration.inMilliseconds}ms'),
  _TextToken(
    'normalDuration',
    '${AppAnimations.normalDuration.inMilliseconds}ms',
  ),
  _TextToken('slowDuration', '${AppAnimations.slowDuration.inMilliseconds}ms'),
  _TextToken('defaultCurve', AppAnimations.defaultCurve.toString()),
  _TextToken('entryCurve', AppAnimations.entryCurve.toString()),
  _TextToken('exitCurve', AppAnimations.exitCurve.toString()),
  _TextToken('springCurve', AppAnimations.springCurve.toString()),
];

final Lead _galleryLead = Lead(
  id: 'gallery-lead',
  address: '4612 S 178 AV E',
  condition: 'Exterior wear',
  notes: 'Tall grass, deferred maintenance, and vacant appearance.',
  status: 'New Lead',
  source: 'Driving For Dollars',
  scoreData: const LeadScoreData(
    brokenWindows: false,
    roofDamage: true,
    tallGrass: true,
    trashInYard: false,
    exteriorWear: true,
    vacantAppearance: true,
    score: 70,
    scoreOverride: false,
  ),
  parcelData: const LeadParcelData(
    ownerName: 'CARRASCO, ROSLY M',
    mailingAddress: 'PO BOX 1122, DALLAS, TX 75201',
    outOfStateOwner: true,
    assessedValue: 190000,
    propertyType: 'Residential',
    lotSize: '0.19 acres',
    yearBuilt: 1978,
  ),
  reminderData: LeadReminderData(
    lastVisitedDate: DateTime(2026, 6, 24),
    reminderDate: DateTime(2026, 7, 1),
    followUpStatus: 'Needs Revisit',
  ),
  offerData: const LeadOfferData(
    arv: 245000,
    repairCost: 35000,
    assignmentFee: 10000,
  ),
  saleData: const LeadSaleData(
    lastSaleDate: '09-01-2020',
    lastSalePrice: 190000,
    deedType: 'WD',
    documentDate: '09-04-2020',
    receptionNo: '2020090101',
  ),
  createdAt: DateTime(2026, 6, 24),
  latitude: 36.26927,
  longitude: -95.85838,
);

final MissionCardData _activeMission = MissionCardData(
  id: 'mission-active',
  areaName: 'North Owasso',
  status: 'active',
  streetCount: 200,
  coveredStreetCount: 47,
  timeBudgetMinutes: 58,
  actualMinutes: null,
  opportunityAtStart: 153,
  leadsFound: 3,
  createdAt: DateTime(2026, 6, 24),
  completedAt: null,
  scheduledDate: DateTime(2026, 6, 26),
);

final MissionCardData _completedMission = MissionCardData(
  id: 'mission-completed',
  areaName: 'North Owasso',
  status: 'completed',
  streetCount: 120,
  coveredStreetCount: 120,
  timeBudgetMinutes: 60,
  actualMinutes: 54,
  opportunityAtStart: 88,
  leadsFound: 6,
  createdAt: DateTime(2026, 6, 20),
  completedAt: DateTime(2026, 6, 20),
  scheduledDate: DateTime(2026, 6, 20),
);

final ParcelProperty _galleryProperty = ParcelProperty(
  accountNo: 'R61400143007690',
  parcelNo: '61400143007690',
  propertyAddress: '13314 E 89 ST N',
  ownerName: 'SLANKARD, PHILLIP D TRUSTEE',
  mailingAddress: '7812 N 146TH E AVE, OWASSO, OK 74055',
  mailingState: 'OK',
  propertyType: 'Residential',
  yearBuilt: 1997,
  squareFeet: 1788,
  lotAcres: 0.21,
  assessedValue: 264400,
  landValue: 23000,
  improvementValue: 241400,
  taxableValue: 170171,
  saleDate: '06-01-2004',
  salePrice: 137000,
  deedType: 'HIST S',
  documentDate: '',
  receptionNo: '2000165732',
  bathrooms: 2,
  stories: 1,
  centroid: const LatLng(36.26927, -95.85838),
  rings: [
    const [
      LatLng(36.2691, -95.8586),
      LatLng(36.2691, -95.8581),
      LatLng(36.2695, -95.8581),
      LatLng(36.2695, -95.8586),
    ],
  ],
  targetScore: 34,
  scoreBreakdown: const {'out_of_state_owner': false},
);
