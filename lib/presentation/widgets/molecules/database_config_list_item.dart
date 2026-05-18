import 'package:backup_database/core/utils/database_type_metadata.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/molecules/config_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double databaseConfigListSubtitleTightGap = 2;

/// **Molecule** — list row for a database configuration (name, subtitle,
/// actions) with brand accent from [DatabaseTypeMetadata].
class DatabaseConfigListItem<T extends Object> extends StatelessWidget {
  const DatabaseConfigListItem({
    required this.config,
    required this.name,
    required this.enabled,
    required this.databaseType,
    required this.subtitle,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
  });

  final T config;
  final String name;
  final bool enabled;
  final DatabaseType databaseType;
  final Widget Function(BuildContext context, T config) subtitle;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final accent = DatabaseTypeMetadata.of(databaseType).accentColor;
    return ConfigListItem(
      name: name,
      icon: FluentIcons.database,
      iconColor: enabled ? accent : null,
      enabled: enabled,
      onToggleEnabled: onToggleEnabled,
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      subtitle: subtitle(context, config),
    );
  }
}
