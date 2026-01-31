import 'package:backup_database/core/theme/app_colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;

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
            ? AppColors.primary
            : FluentTheme.of(context).resources.textFillColorSecondary);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: enabled
              ? AppColors.primary.withValues(alpha: 0.2)
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
              const SizedBox(width: 8),
            ],
            if (onToggleEnabled != null)
              ToggleSwitch(checked: enabled, onChanged: onToggleEnabled),
            if ((onEdit != null || onDelete != null) && onToggleEnabled != null)
              const SizedBox(width: 8),
            if (onEdit != null || onDelete != null) _buildMenuButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context) {
    final items = <material.PopupMenuItem<String>>[];

    if (onEdit != null) {
      items.add(
        const material.PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(FluentIcons.edit, size: 16),
              SizedBox(width: 8),
              Text('Editar'),
            ],
          ),
        ),
      );
    }

    if (onDuplicate != null) {
      items.add(
        const material.PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(FluentIcons.copy, size: 16),
              SizedBox(width: 8),
              Text('Duplicar'),
            ],
          ),
        ),
      );
    }

    if (onDelete != null) {
      items.add(
        const material.PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(FluentIcons.delete, size: 16, color: AppColors.delete),
              SizedBox(width: 8),
              Text('Excluir', style: TextStyle(color: AppColors.delete)),
            ],
          ),
        ),
      );
    }

    final menuBackgroundColor =
        FluentTheme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1F1F1F)
        : const Color(0xFFFFFFFF);

    return material.Material(
      color: Colors.transparent,
      child: material.PopupMenuButton<String>(
        color: menuBackgroundColor,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: FluentTheme.of(context).resources.controlStrokeColorDefault,
          ),
        ),
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit?.call();
            case 'duplicate':
              onDuplicate?.call();
            case 'delete':
              onDelete?.call();
          }
        },
        itemBuilder: (context) => items,
        child: material.InkWell(
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              FluentIcons.more_vertical,
              size: 20,
              color: FluentTheme.of(context).resources.textFillColorPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
