import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/sybase_config.dart';
import '../common/config_list_item.dart';

class SybaseConfigListItem extends StatelessWidget {
  final SybaseConfig config;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;

  const SybaseConfigListItem({
    super.key,
    required this.config,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return ConfigListItem(
      name: config.name,
      icon: FluentIcons.database,
      enabled: config.enabled,
      onToggleEnabled: onToggleEnabled,
      onEdit: onEdit,
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
