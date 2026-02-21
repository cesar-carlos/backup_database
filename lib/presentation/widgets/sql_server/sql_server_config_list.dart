import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SqlServerConfigList extends StatelessWidget {
  const SqlServerConfigList({
    required this.configs,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
  });
  final List<SqlServerConfig> configs;
  final void Function(SqlServerConfig)? onEdit;
  final void Function(SqlServerConfig)? onDuplicate;
  final void Function(String)? onDelete;
  final void Function(String, bool)? onToggleEnabled;

  String _t(BuildContext context, String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  Widget build(BuildContext context) {
    if (configs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _t(
              context,
              'Nenhuma configuração encontrada',
              'No configuration found',
            ),
          ),
        ),
      );
    }

    return AppCard(
      child: AppDataGrid<SqlServerConfig>(
        minWidth: 1000,
        columns: [
          AppDataGridColumn<SqlServerConfig>(
            label: _t(context, 'Nome', 'Name'),
            width: const FlexColumnWidth(1.8),
            cellBuilder: (context, row) => Text(row.name),
          ),
          AppDataGridColumn<SqlServerConfig>(
            label: _t(context, 'Servidor', 'Server'),
            width: const FlexColumnWidth(1.9),
            cellBuilder: (context, row) =>
                Text('${row.server}:${row.portValue}'),
          ),
          AppDataGridColumn<SqlServerConfig>(
            label: _t(context, 'Banco', 'Database'),
            width: const FlexColumnWidth(1.5),
            cellBuilder: (context, row) => Text(row.databaseValue),
          ),
          AppDataGridColumn<SqlServerConfig>(
            label: _t(context, 'Usuario', 'User'),
            width: const FlexColumnWidth(1.5),
            cellBuilder: (context, row) => Text(row.username),
          ),
          AppDataGridColumn<SqlServerConfig>(
            label: _t(context, 'Status', 'Status'),
            width: const FlexColumnWidth(1.2),
            cellBuilder: (context, row) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToggleSwitch(
                  checked: row.enabled,
                  onChanged: onToggleEnabled != null
                      ? (enabled) => onToggleEnabled!(row.id, enabled)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  row.enabled
                      ? _t(context, 'Ativo', 'Active')
                      : _t(context, 'Inativo', 'Inactive'),
                ),
              ],
            ),
          ),
        ],
        actions: [
          AppDataGridAction<SqlServerConfig>(
            icon: FluentIcons.edit,
            tooltip: _t(context, 'Editar', 'Edit'),
            onPressed: (row) => onEdit?.call(row),
            isEnabled: (_) => onEdit != null,
          ),
          AppDataGridAction<SqlServerConfig>(
            icon: FluentIcons.copy,
            tooltip: _t(context, 'Duplicar', 'Duplicate'),
            onPressed: (row) => onDuplicate?.call(row),
            isEnabled: (_) => onDuplicate != null,
          ),
          AppDataGridAction<SqlServerConfig>(
            icon: FluentIcons.delete,
            iconColor: AppColors.error,
            tooltip: _t(context, 'Excluir', 'Delete'),
            onPressed: (row) => onDelete?.call(row.id),
            isEnabled: (_) => onDelete != null,
          ),
        ],
        rows: configs,
      ),
    );
  }
}
