import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/presentation/widgets/common/config_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SqlServerConfigListItem extends StatelessWidget {
  const SqlServerConfigListItem({
    required this.config,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
  });
  final SqlServerConfig config;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return ConfigListItem(
      name: config.name,
      icon: FluentIcons.database,
      enabled: config.enabled,
      onToggleEnabled: onToggleEnabled,
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text('${config.server}:${config.port}'),
          const SizedBox(height: 2),
          Text('Banco: ${config.database}'),
          const SizedBox(height: 2),
          Text('Usuário: ${config.username}'),
        ],
      ),
    );
  }
}
