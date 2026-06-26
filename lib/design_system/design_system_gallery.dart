import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
