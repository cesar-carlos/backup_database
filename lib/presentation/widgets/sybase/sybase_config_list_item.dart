import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/presentation/widgets/common/config_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SybaseConfigListItem extends StatelessWidget {
  const SybaseConfigListItem({
    required this.config,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
  });
  final SybaseConfig config;
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
          Text('Servidor: ${config.serverName}:${config.port}'),
          const SizedBox(height: 2),
          Text('Banco: ${config.databaseName}'),
          const SizedBox(height: 2),
          Text('Usuário: ${config.username}'),
        ],
      ),
    );
  }
}
