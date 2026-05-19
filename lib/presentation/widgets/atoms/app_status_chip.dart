import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum AppStatusChipTone {
  neutral,
  info,
  success,
  warning,
  danger,
}

/// **Atom** - compact semantic chip for types, statuses and tags.
class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    required this.label,
    super.key,
    this.color,
    this.icon,
    this.tone = AppStatusChipTone.neutral,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final AppStatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? _toneColor(context);
    final textStyle = FluentTheme.of(
      context,
    ).typography.caption?.copyWith(color: resolvedColor);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.12),
        borderRadius: AppRadius.circularSm,
        border: Border.all(
          color: resolvedColor.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: resolvedColor),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }

  Color _toneColor(BuildContext context) {
    final colors = context.colors;
    return switch (tone) {
      AppStatusChipTone.neutral =>
        FluentTheme.of(context).accentColor.defaultBrushFor(
          FluentTheme.of(context).brightness,
        ),
      AppStatusChipTone.info => colors.info,
      AppStatusChipTone.success => colors.success,
      AppStatusChipTone.warning => colors.warning,
      AppStatusChipTone.danger => colors.danger,
    };
  }
}
