import 'package:flutter/material.dart';

import '../../../domain/entities/sql_server_config.dart';
import 'sql_server_config_list_item.dart';

class SqlServerConfigList extends StatelessWidget {
  final List<SqlServerConfig> configs;
  final Function(SqlServerConfig)? onEdit;
  final Function(SqlServerConfig)? onDuplicate;
  final Function(String)? onDelete;
  final Function(String, bool)? onToggleEnabled;

  const SqlServerConfigList({
    super.key,
    required this.configs,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
  });

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
          onDuplicate:
              onDuplicate != null ? () => onDuplicate!(config) : null,
          onDelete: onDelete != null ? () => onDelete!(config.id) : null,
          onToggleEnabled: onToggleEnabled != null
              ? (enabled) => onToggleEnabled!(config.id, enabled)
              : null,
        );
      },
    );
  }
}

