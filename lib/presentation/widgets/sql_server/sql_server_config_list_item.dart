import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/presentation/widgets/common/database_config_list_item.dart';
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
    return DatabaseConfigListItem<SqlServerConfig>(
      config: config,
      name: config.name,
      enabled: config.enabled,
      databaseType: DatabaseType.sqlServer,
      subtitle: _subtitle,
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      onToggleEnabled: onToggleEnabled,
    );
  }

  Widget _subtitle(BuildContext context, SqlServerConfig c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xs),
        Text('${c.server}:${c.port}'),
        const SizedBox(height: databaseConfigListSubtitleTightGap),
        Text(
          '${appLocaleString(context, 'Banco', 'Database')}: ${c.databaseValue}',
        ),
        const SizedBox(height: databaseConfigListSubtitleTightGap),
        Text(
          '${appLocaleString(context, 'Usuario', 'User')}: ${c.username}',
        ),
      ],
    );
  }
}
