import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _badgeLabelFontSize = 11;
const EdgeInsets _badgePadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.sm,
  vertical: AppSpacing.xs,
);

/// **Molecule** — section title, total count, optional active/inactive badges.
class SectionHeaderWithStatusBadges extends StatelessWidget {
  const SectionHeaderWithStatusBadges({
    required this.label,
    required this.count,
    required this.activeCount,
    required this.inactiveCount,
    super.key,
  });

  final String label;
  final int count;
  final int activeCount;
  final int inactiveCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appSemanticColors;
    final subtitleStyle = FluentTheme.of(context).typography.subtitle;
    final captionStyle = FluentTheme.of(context).typography.caption;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label, style: subtitleStyle),
        Text('($count)', style: captionStyle),
        if (activeCount > 0)
          _SectionStatusBadge(
            label: _activeCountLabel(context, activeCount),
            badgeColor: colors.success,
          ),
        if (inactiveCount > 0)
          _SectionStatusBadge(
            label: _inactiveCountLabel(context, inactiveCount),
            badgeColor: colors.danger,
          ),
      ],
    );
  }
}

String _activeCountLabel(BuildContext context, int countValue) {
  return appLocaleString(
    context,
    countValue == 1 ? '1 ativa' : '$countValue ativas',
    countValue == 1 ? '1 active' : '$countValue active',
  );
}

String _inactiveCountLabel(BuildContext context, int countValue) {
  return appLocaleString(
    context,
    countValue == 1 ? '1 inativa' : '$countValue inativas',
    countValue == 1 ? '1 inactive' : '$countValue inactive',
  );
}

class _SectionStatusBadge extends StatelessWidget {
  const _SectionStatusBadge({
    required this.label,
    required this.badgeColor,
  });

  final String label;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: AppRadius.circularLg,
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: _badgePadding,
        child: Text(
          label,
          style: TextStyle(
            fontSize: _badgeLabelFontSize,
            color: badgeColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
