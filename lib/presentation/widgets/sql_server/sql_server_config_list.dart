import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/presentation/widgets/sql_server/sql_server_config_list_item.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    if (configs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Nenhuma configuração encontrada'),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: configs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final config = configs[index];
        return SqlServerConfigListItem(
          config: config,
          onEdit: onEdit != null ? () => onEdit!(config) : null,
          onDuplicate: onDuplicate != null ? () => onDuplicate!(config) : null,
          onDelete: onDelete != null ? () => onDelete!(config.id) : null,
          onToggleEnabled: onToggleEnabled != null
              ? (enabled) => onToggleEnabled!(config.id, enabled)
              : null,
        );
      },
    );
  }
}
