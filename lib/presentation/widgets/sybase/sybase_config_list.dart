import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/presentation/widgets/sybase/sybase_config_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SybaseConfigList extends StatelessWidget {
  const SybaseConfigList({
    required this.configs,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
  });
  final List<SybaseConfig> configs;
  final void Function(SybaseConfig)? onEdit;
  final void Function(SybaseConfig)? onDuplicate;
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
              'Nenhuma configuracao encontrada',
              'No configuration found',
            ),
          ),
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
