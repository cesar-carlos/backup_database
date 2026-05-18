import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/presentation/widgets/common/app_card.dart';
import 'package:backup_database/presentation/widgets/common/app_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DatabaseConfigGridRow {
  const DatabaseConfigGridRow({
    required this.name,
    required this.serverEndpoint,
    required this.database,
    required this.username,
    required this.id,
    required this.enabled,
  });

  final String name;
  final String serverEndpoint;
  final String database;
  final String username;
  final String id;
  final bool enabled;
}

/// **Organism** — shared data grid for database configuration lists.
class DatabaseConfigDataGrid<T extends Object> extends StatelessWidget {
  const DatabaseConfigDataGrid({
    required this.configs,
    required this.rowOf,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
    this.minWidth = 1000,
  });

  final List<T> configs;
  final DatabaseConfigGridRow Function(T row) rowOf;
  final void Function(T)? onEdit;
  final void Function(T)? onDuplicate;
  final void Function(String)? onDelete;
  final void Function(String, bool)? onToggleEnabled;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    if (configs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(
            appLocaleString(
              context,
              'Nenhuma configuração encontrada',
              'No configuration found',
            ),
          ),
        ),
      );
    }

    return AppCard(
      child: AppDataGrid<T>(
        minWidth: minWidth,
        columns: [
          AppDataGridColumn<T>(
            label: appLocaleString(context, 'Nome', 'Name'),
            width: const FlexColumnWidth(1.8),
            cellBuilder: (context, row) => Text(rowOf(row).name),
          ),
          AppDataGridColumn<T>(
            label: appLocaleString(context, 'Servidor', 'Server'),
            width: const FlexColumnWidth(1.9),
            cellBuilder: (context, row) => Text(rowOf(row).serverEndpoint),
          ),
          AppDataGridColumn<T>(
            label: appLocaleString(context, 'Banco', 'Database'),
            width: const FlexColumnWidth(1.5),
            cellBuilder: (context, row) => Text(rowOf(row).database),
          ),
          AppDataGridColumn<T>(
            label: appLocaleString(context, 'Usuario', 'User'),
            width: const FlexColumnWidth(1.5),
            cellBuilder: (context, row) => Text(rowOf(row).username),
          ),
          AppDataGridColumn<T>(
            label: appLocaleString(context, 'Status', 'Status'),
            width: const FlexColumnWidth(1.2),
            cellBuilder: (context, row) {
              final view = rowOf(row);
              return Row(
                children: [
                  ToggleSwitch(
                    checked: view.enabled,
                    onChanged: onToggleEnabled != null
                        ? (enabled) => onToggleEnabled!(view.id, enabled)
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      view.enabled
                          ? appLocaleString(context, 'Ativo', 'Active')
                          : appLocaleString(context, 'Inativo', 'Inactive'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
        actions: [
          AppDataGridAction<T>(
            icon: FluentIcons.edit,
            tooltip: appLocaleString(context, 'Editar', 'Edit'),
            onPressed: (row) => onEdit?.call(row),
            isEnabled: (_) => onEdit != null,
          ),
          AppDataGridAction<T>(
            icon: FluentIcons.copy,
            tooltip: appLocaleString(context, 'Duplicar', 'Duplicate'),
            onPressed: (row) => onDuplicate?.call(row),
            isEnabled: (_) => onDuplicate != null,
          ),
          AppDataGridAction<T>(
            icon: FluentIcons.delete,
            iconColor: AppColors.error,
            tooltip: appLocaleString(context, 'Excluir', 'Delete'),
            onPressed: (row) => onDelete?.call(rowOf(row).id),
            isEnabled: (_) => onDelete != null,
          ),
        ],
        rows: configs,
      ),
    );
  }
}
