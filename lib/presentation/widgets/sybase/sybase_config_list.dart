import 'package:flutter/material.dart';

import '../../../domain/entities/sybase_config.dart';
import 'sybase_config_list_item.dart';

class SybaseConfigList extends StatelessWidget {
  final List<SybaseConfig> configs;
  final Function(SybaseConfig)? onEdit;
  final Function(String)? onDelete;
  final Function(String, bool)? onToggleEnabled;

  const SybaseConfigList({
    super.key,
    required this.configs,
    this.onEdit,
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
        return SybaseConfigListItem(
          config: config,
          onEdit: onEdit != null ? () => onEdit!(config) : null,
          onDelete: onDelete != null ? () => onDelete!(config.id) : null,
          onToggleEnabled: onToggleEnabled != null
              ? (enabled) => onToggleEnabled!(config.id, enabled)
              : null,
        );
      },
    );
  }
}

