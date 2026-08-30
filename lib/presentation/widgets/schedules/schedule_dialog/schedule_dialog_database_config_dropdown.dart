import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ScheduleDialogDatabaseConfigDropdown extends StatelessWidget {
  const ScheduleDialogDatabaseConfigDropdown({
    required this.databaseType,
    required this.selectedConfigId,
    required this.sqlServerConfigsLength,
    required this.sybaseConfigsLength,
    required this.postgresConfigsLength,
    required this.firebirdConfigsLength,
    required this.onSqlServerConfigsSynced,
    required this.onSybaseConfigsSynced,
    required this.onPostgresConfigsSynced,
    required this.onFirebirdConfigsSynced,
    required this.onSelectedConfigIdChanged,
    super.key,
  });

  final DatabaseType databaseType;
  final String? selectedConfigId;
  final int sqlServerConfigsLength;
  final int sybaseConfigsLength;
  final int postgresConfigsLength;
  final int firebirdConfigsLength;
  final ValueChanged<List<SqlServerConfig>> onSqlServerConfigsSynced;
  final ValueChanged<List<SybaseConfig>> onSybaseConfigsSynced;
  final ValueChanged<List<PostgresConfig>> onPostgresConfigsSynced;
  final ValueChanged<List<FirebirdConfig>> onFirebirdConfigsSynced;
  final ValueChanged<String?> onSelectedConfigIdChanged;

  @override
  Widget build(BuildContext context) {
    switch (databaseType) {
      case DatabaseType.firebird:
        return Consumer<FirebirdConfigProvider>(
          builder: (BuildContext context, FirebirdConfigProvider provider, _) {
            return _SyncedConfigDropdown<FirebirdConfig>(
              configs: provider.configs,
              cachedLength: firebirdConfigsLength,
              selectedConfigId: selectedConfigId,
              itemLabel: (FirebirdConfig config) =>
                  '${config.name} (${config.host}:${config.port}/'
                  '${config.databaseFile})',
              onConfigsSynced: onFirebirdConfigsSynced,
              onSelectedConfigIdChanged: onSelectedConfigIdChanged,
            );
          },
        );
      case DatabaseType.sqlServer:
        return Consumer<SqlServerConfigProvider>(
          builder: (BuildContext context, SqlServerConfigProvider provider, _) {
            return _SyncedConfigDropdown<SqlServerConfig>(
              configs: provider.configs,
              cachedLength: sqlServerConfigsLength,
              selectedConfigId: selectedConfigId,
              itemLabel: (SqlServerConfig config) =>
                  '${config.name} (${config.server}:${config.database})',
              onConfigsSynced: onSqlServerConfigsSynced,
              onSelectedConfigIdChanged: onSelectedConfigIdChanged,
            );
          },
        );
      case DatabaseType.postgresql:
        return Consumer<PostgresConfigProvider>(
          builder: (BuildContext context, PostgresConfigProvider provider, _) {
            return _SyncedConfigDropdown<PostgresConfig>(
              configs: provider.configs,
              cachedLength: postgresConfigsLength,
              selectedConfigId: selectedConfigId,
              itemLabel: (PostgresConfig config) =>
                  '${config.name} (${config.host}:${config.port}/'
                  '${config.database})',
              onConfigsSynced: onPostgresConfigsSynced,
              onSelectedConfigIdChanged: onSelectedConfigIdChanged,
            );
          },
        );
      case DatabaseType.sybase:
        return Consumer<SybaseConfigProvider>(
          builder: (BuildContext context, SybaseConfigProvider provider, _) {
            return _SyncedConfigDropdown<SybaseConfig>(
              configs: provider.configs,
              cachedLength: sybaseConfigsLength,
              selectedConfigId: selectedConfigId,
              itemLabel: (SybaseConfig config) =>
                  '${config.name} (${config.serverName}:${config.port})',
              onConfigsSynced: onSybaseConfigsSynced,
              onSelectedConfigIdChanged: onSelectedConfigIdChanged,
            );
          },
        );
    }
  }
}

class _SyncedConfigDropdown<T extends DatabaseConnectionConfig>
    extends StatefulWidget {
  const _SyncedConfigDropdown({
    required this.configs,
    required this.cachedLength,
    required this.selectedConfigId,
    required this.itemLabel,
    required this.onConfigsSynced,
    required this.onSelectedConfigIdChanged,
  });

  final List<T> configs;
  final int cachedLength;
  final String? selectedConfigId;
  final String Function(T config) itemLabel;
  final ValueChanged<List<T>> onConfigsSynced;
  final ValueChanged<String?> onSelectedConfigIdChanged;

  @override
  State<_SyncedConfigDropdown<T>> createState() =>
      _SyncedConfigDropdownState<T>();
}

class _SyncedConfigDropdownState<T extends DatabaseConnectionConfig>
    extends State<_SyncedConfigDropdown<T>> {
  @override
  Widget build(BuildContext context) {
    final items = widget.configs.map((T config) {
      return ComboBoxItem<String>(
        value: config.id,
        child: Text(widget.itemLabel(config)),
      );
    }).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.cachedLength != widget.configs.length) {
        widget.onConfigsSynced(widget.configs);
      }
    });

    final String? validValue;
    if (widget.selectedConfigId != null) {
      final exists = items.any(
        (ComboBoxItem<String> item) => item.value == widget.selectedConfigId,
      );
      validValue = exists ? widget.selectedConfigId : null;
      if (!exists) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onSelectedConfigIdChanged(null);
          }
        });
      }
    } else {
      validValue = null;
    }

    return AppDropdown<String>(
      label: 'Configuração de Banco',
      value: validValue,
      placeholder: Text(
        items.isEmpty
            ? 'Nenhuma configuração disponível'
            : 'Selecione uma configuração',
      ),
      items: items.isEmpty
          ? [
              ComboBoxItem<String>(
                child: Text(
                  'Nenhuma configuração disponível',
                  style: FluentTheme.of(context).typography.caption?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ]
          : items,
      onChanged: items.isEmpty ? null : widget.onSelectedConfigIdChanged,
    );
  }
}
