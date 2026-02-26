import 'package:backup_database/domain/entities/server_credential.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ServerCredentialGrid extends StatelessWidget {
  const ServerCredentialGrid({
    required this.credentials,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
    super.key,
  });

  final List<ServerCredential> credentials;
  final ValueChanged<ServerCredential> onEdit;
  final ValueChanged<String> onDelete;
  final void Function(ServerCredential credential, bool active) onToggleActive;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: AppDataGrid<ServerCredential>(
        minWidth: 900,
        columns: [
          AppDataGridColumn<ServerCredential>(
            label: 'Nome',
            width: const FlexColumnWidth(1.8),
            cellBuilder: (context, row) => Text(row.name),
          ),
          AppDataGridColumn<ServerCredential>(
            label: 'Server ID',
            width: const FlexColumnWidth(1.6),
            cellBuilder: (context, row) => SelectableText(row.serverId),
          ),
          AppDataGridColumn<ServerCredential>(
            label: 'Descrição',
            width: const FlexColumnWidth(2.8),
            cellBuilder: (context, row) => Text(
              (row.description?.trim().isNotEmpty ?? false)
                  ? row.description!
                  : '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppDataGridColumn<ServerCredential>(
            label: 'Status',
            width: const FlexColumnWidth(1.3),
            cellBuilder: (context, row) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToggleSwitch(
                  checked: row.isActive,
                  onChanged: (active) => onToggleActive(row, active),
                ),
                const SizedBox(width: 8),
                Text(row.isActive ? 'Ativo' : 'Inativo'),
              ],
            ),
          ),
        ],
        actions: [
          AppDataGridAction<ServerCredential>(
            icon: FluentIcons.edit,
            tooltip: 'Editar',
            onPressed: onEdit,
          ),
          AppDataGridAction<ServerCredential>(
            icon: FluentIcons.delete,
            tooltip: 'Excluir',
            onPressed: (row) => onDelete(row.id),
          ),
        ],
        rows: credentials,
      ),
    );
  }
}
