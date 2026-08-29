import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum AppCalloutTone { info, warning, danger, success }

const double _iconSize = 18;
const double _fillAlpha = 0.10;
const double _strokeAlpha = 0.30;

/// **Atom** — inline hint / warning surface with semantic tone.
class AppCallout extends StatelessWidget {
  const AppCallout({
    required this.message,
    super.key,
    this.tone = AppCalloutTone.info,
    this.icon,
  });

  final String message;
  final AppCalloutTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context);
    final resolvedIcon = icon ?? _toneIcon;

    return Container(
      padding: AppSpacing.paddingSm,
      decoration: BoxDecoration(
        color: color.withValues(alpha: _fillAlpha),
        borderRadius: AppRadius.circularMd,
        border: Border.all(color: color.withValues(alpha: _strokeAlpha)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(resolvedIcon, size: _iconSize, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: FluentTheme.of(context).typography.caption,
            ),
          ),
        ],
      ),
    );
  }

  IconData get _toneIcon {
    return switch (tone) {
      AppCalloutTone.info => FluentIcons.info,
      AppCalloutTone.warning => FluentIcons.warning,
      AppCalloutTone.danger => FluentIcons.error_badge,
      AppCalloutTone.success => FluentIcons.completed,
    };
  }

  Color _toneColor(BuildContext context) {
    final colors = context.colors;
    return switch (tone) {
      AppCalloutTone.info => colors.info,
      AppCalloutTone.warning => colors.warning,
      AppCalloutTone.danger => colors.danger,
      AppCalloutTone.success => colors.success,
    };
  }
}
