import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — generic configuration row with toggle and row actions.
class ConfigListItem extends StatelessWidget {
  const ConfigListItem({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    super.key,
    this.iconColor,
    this.onToggleEnabled,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.trailingAction,
  });
  final String name;
  final Widget subtitle;
  final IconData icon;
  final Color? iconColor;
  final bool enabled;
  final ValueChanged<bool>? onToggleEnabled;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor =
        iconColor ??
        (enabled
            ? AppPalette.primary
            : FluentTheme.of(context).resources.textFillColorSecondary);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: enabled
              ? AppPalette.primary.withValues(alpha: 0.2)
              : FluentTheme.of(context).resources.cardStrokeColorDefault,
          child: Icon(icon, color: effectiveIconColor),
        ),
        title: Text(
          name,
          style: FluentTheme.of(
            context,
          ).typography.subtitle?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailingAction != null) ...[
              trailingAction!,
              const SizedBox(width: AppSpacing.sm),
            ],
            if (onToggleEnabled != null)
              ToggleSwitch(checked: enabled, onChanged: onToggleEnabled),
            if (onEdit != null) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                icon: const Icon(FluentIcons.edit),
                onPressed: onEdit,
              ),
            ],
            if (onDelete != null) ...[
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                icon: const Icon(FluentIcons.delete),
                onPressed: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
