import 'package:flutter/material.dart';

import '../tokens/app_animations.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

class AppTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingIconTap;
  final bool showClearButton;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final int? maxLines;
  final bool readOnly;
  final bool autofocus;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.helperText,
    this.leadingIcon,
    this.trailingIcon,
    this.onTrailingIconTap,
    this.showClearButton = false,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.onEditingComplete,
    this.maxLines = 1,
    this.readOnly = false,
    this.autofocus = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late TextEditingController _controller;
  late bool _ownsController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_handleTextChanged);
      if (_ownsController) _controller.dispose();
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    if (_ownsController) _controller.dispose();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (mounted) setState(() {});
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final tertiaryText = dark
        ? AppColors.textTertiaryDark
        : AppColors.textTertiaryLight;
    final borderColor = widget.errorText != null
        ? AppColors.danger
        : (_focusNode.hasFocus
              ? AppColors.primary
              : (dark ? AppColors.borderDark : AppColors.borderLight));
    final fillColor = Theme.of(context).inputDecorationTheme.fillColor;
    final showClearButton =
        widget.showClearButton &&
        _controller.text.isNotEmpty &&
        _focusNode.hasFocus;
    final trailingIcon = showClearButton
        ? Icons.cancel_rounded
        : widget.trailingIcon;
    final trailingAction = showClearButton ? _clear : widget.onTrailingIconTap;

    return Opacity(
      opacity: widget.readOnly
          ? (AppSpacing.massive + AppSpacing.sm - AppSpacing.xs / 2) / 100
          : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label != null) ...[
            Text(
              widget.label!,
              style: AppTypography.bodySmall(color: secondaryText),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AnimatedContainer(
            duration: AppAnimations.fastDuration,
            curve: AppAnimations.defaultCurve,
            constraints: const BoxConstraints(
              minHeight: AppSpacing.touchTarget,
            ),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(
                AppSpacing.buttonBorderRadius,
              ),
              border: Border.all(color: borderColor),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              onChanged: widget.onChanged,
              onEditingComplete: widget.onEditingComplete,
              maxLines: widget.obscureText ? 1 : widget.maxLines,
              readOnly: widget.readOnly,
              autofocus: widget.autofocus,
              showCursor: !widget.readOnly,
              style: AppTypography.bodyLarge(dark: dark),
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: widget.leadingIcon == null
                    ? null
                    : Icon(
                        widget.leadingIcon,
                        color: tertiaryText,
                        size: AppSpacing.xl,
                      ),
                suffixIcon: trailingIcon == null
                    ? null
                    : IconButton(
                        onPressed: trailingAction,
                        icon: Icon(
                          trailingIcon,
                          color: tertiaryText,
                          size: showClearButton
                              ? AppSpacing.lg + AppSpacing.xs / 2
                              : AppSpacing.xl,
                        ),
                      ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
              ).applyDefaults(Theme.of(context).inputDecorationTheme),
            ),
          ),
          if (widget.errorText != null || widget.helperText != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.errorText ?? widget.helperText!,
              style: AppTypography.bodySmall(
                color: widget.errorText != null
                    ? AppColors.danger
                    : secondaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
