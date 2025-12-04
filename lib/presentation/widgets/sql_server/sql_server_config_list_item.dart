import 'package:fluent_ui/fluent_ui.dart';

import '../../../domain/entities/sql_server_config.dart';
import '../common/config_list_item.dart';

class SqlServerConfigListItem extends StatelessWidget {
  final SqlServerConfig config;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;

  const SqlServerConfigListItem({
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
