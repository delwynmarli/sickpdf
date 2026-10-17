import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared building blocks for tool screens so every tool uses the same
/// spacing, typography, status treatment, and primary-action layout.

/// A titled section used to group related controls inside a tool screen.
class ToolSection extends StatelessWidget {
  const ToolSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.lg),
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// A one-line intro explaining what a tool does and that files stay local.
class ToolIntro extends StatelessWidget {
  const ToolIntro({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The currently selected input file, shown consistently across tools.
class SelectedFileCard extends StatelessWidget {
  const SelectedFileCard({
    super.key,
    required this.name,
    this.detail,
    this.onReplace,
  });

  final String name;
  final String? detail;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 22,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (onReplace != null)
              IconButton(
                tooltip: 'Replace selected file',
                onPressed: onReplace,
                icon: const Icon(Icons.swap_horiz),
              ),
          ],
        ),
      ),
    );
  }
}

/// Empty-state panel shown before an input is selected.
///
/// When [onSelect] is provided, the whole panel is an interactive target that
/// triggers the same file-selection action as the tool's select button, with
/// a visible pressed state and full-panel semantics. The inner icon is purely
/// decorative so taps pass through to the panel.
class ToolEmptyState extends StatelessWidget {
  const ToolEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onSelect,
    this.selectLabel,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Invoked when any part of the panel is tapped. Typically the same
  /// callback used by the tool's "Select PDF" button so the picker can never
  /// be triggered twice.
  final VoidCallback? onSelect;

  /// Short action hint shown under the message when the panel is tappable.
  final String? selectLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(AppRadius.md);
    final content = Column(
      children: [
        Icon(icon, size: 30, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (onSelect != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                selectLabel ?? 'Tap to select',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    if (onSelect == null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xxl,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: borderRadius,
          border: Border.all(color: theme.dividerColor),
        ),
        child: content,
      );
    }

    return Semantics(
      button: true,
      label: '$title. $message',
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onSelect,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xxl,
            ),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(color: theme.dividerColor),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Inline, accessible status message for success, error, and info states.
///
/// Uses an icon plus text so status is never conveyed by color alone, and
/// announces changes to screen readers via [Semantics.liveRegion].
class ToolStatus extends StatelessWidget {
  const ToolStatus({super.key, required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? AppColors.danger : AppColors.success;
    final icon = isError
        ? Icons.error_outline
        : (message.toLowerCase().contains('cancel')
              ? Icons.info_outline
              : Icons.check_circle_outline);

    return Semantics(
      liveRegion: true,
      label: '${isError ? 'Error' : 'Status'}: $message',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
