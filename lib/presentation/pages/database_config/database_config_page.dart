import 'dart:async';

import 'package:backup_database/application/providers/database_connection_test_snapshot.dart';
import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/core/utils/database_type_metadata.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/firebird/firebird.dart';
import 'package:backup_database/presentation/widgets/postgres/postgres.dart';
import 'package:backup_database/presentation/widgets/sql_server/sql_server.dart';
import 'package:backup_database/presentation/widgets/sybase/sybase.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

part 'database_config_page_actions.dart';
part 'database_config_page_content.dart';

class DatabaseConfigPage extends StatefulWidget {
  const DatabaseConfigPage({super.key});

  @override
  State<DatabaseConfigPage> createState() => _DatabaseConfigPageState();
}

class _DatabaseConfigPageState extends State<DatabaseConfigPage>
    with _DatabaseConfigPageActions {
  bool _hideFirebirdRemoteUi(BuildContext context) {
    if (currentAppMode != AppMode.client) {
      return false;
    }
    try {
      final scp = context.watch<ServerConnectionProvider>();
      return scp.isConnected && !scp.isFirebirdSupported;
    } on ProviderNotFoundException {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<SqlServerConfigProvider>().loadConfigs());
      unawaited(context.read<SybaseConfigProvider>().loadConfigs());
      unawaited(context.read<PostgresConfigProvider>().loadConfigs());
      unawaited(context.read<FirebirdConfigProvider>().loadConfigs());
    });
  }

  void _refresh() {
    unawaited(context.read<SqlServerConfigProvider>().loadConfigs());
    unawaited(context.read<SybaseConfigProvider>().loadConfigs());
    unawaited(context.read<PostgresConfigProvider>().loadConfigs());
    unawaited(context.read<FirebirdConfigProvider>().loadConfigs());
  }

  void _toggleSqlServerEnabled(String id, bool enabled) {
    unawaited(
      context.read<SqlServerConfigProvider>().toggleEnabled(id, enabled),
    );
  }

  void _toggleSybaseEnabled(String id, bool enabled) {
    unawaited(
      context.read<SybaseConfigProvider>().toggleEnabled(id, enabled),
    );
  }

  void _togglePostgresEnabled(String id, bool enabled) {
    unawaited(
      context.read<PostgresConfigProvider>().toggleEnabled(id, enabled),
    );
  }

  void _toggleFirebirdEnabled(String id, bool enabled) {
    unawaited(
      context.read<FirebirdConfigProvider>().toggleEnabled(id, enabled),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sqlProvider = context.watch<SqlServerConfigProvider>();
    final sybaseProvider = context.watch<SybaseConfigProvider>();
    final postgresProvider = context.watch<PostgresConfigProvider>();
    final firebirdProvider = context.watch<FirebirdConfigProvider>();
    final hideFirebirdRemote = _hideFirebirdRemoteUi(context);

    return AppPageScaffold(
      title: appLocaleString(
        context,
        'Configurações de banco de dados',
        'Database configuration',
      ),
      actions: [
        AppPageAction(
          label: appLocaleString(context, 'Atualizar', 'Refresh'),
          icon: FluentIcons.refresh,
          onPressed: _refresh,
        ),
        AppPageAction(
          label: appLocaleString(
            context,
            'Nova configuração',
            'New configuration',
          ),
          icon: FluentIcons.add,
          isPrimary: true,
          onPressed: _showNewConfigDialog,
        ),
      ],
      body: _DatabaseConfigsContent(
        sqlProvider: sqlProvider,
        sybaseProvider: sybaseProvider,
        postgresProvider: postgresProvider,
        firebirdProvider: firebirdProvider,
        hideFirebirdSection: hideFirebirdRemote,
        onRefresh: _refresh,
        onCreateConfig: _showNewConfigDialog,
        onEditSql: _showConfigDialog,
        onDuplicateSql: _duplicateSqlServerConfig,
        onDeleteSql: _confirmDeleteSqlServer,
        onToggleSqlEnabled: _toggleSqlServerEnabled,
        onEditSybase: _showSybaseConfigDialog,
        onDuplicateSybase: _duplicateSybaseConfig,
        onDeleteSybase: _confirmDeleteSybase,
        onToggleSybaseEnabled: _toggleSybaseEnabled,
        onEditPostgres: _showPostgresConfigDialog,
        onDuplicatePostgres: _duplicatePostgresConfig,
        onDeletePostgres: _confirmDeletePostgres,
        onTogglePostgresEnabled: _togglePostgresEnabled,
        onEditFirebird: _showFirebirdConfigDialog,
        onDuplicateFirebird: _duplicateFirebirdConfig,
        onDeleteFirebird: _confirmDeleteFirebird,
        onToggleFirebirdEnabled: _toggleFirebirdEnabled,
      ),
    );
  }
}
