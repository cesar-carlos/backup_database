import 'dart:async';

import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
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

class DatabaseConfigPage extends StatefulWidget {
  const DatabaseConfigPage({super.key});

  @override
  State<DatabaseConfigPage> createState() => _DatabaseConfigPageState();
}

class _DatabaseConfigPageState extends State<DatabaseConfigPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(context.read<SqlServerConfigProvider>().loadConfigs());
      unawaited(context.read<SybaseConfigProvider>().loadConfigs());
    });
  }

  void _refresh() {
    unawaited(context.read<SqlServerConfigProvider>().loadConfigs());
    unawaited(context.read<SybaseConfigProvider>().loadConfigs());
    unawaited(context.read<PostgresConfigProvider>().loadConfigs());
    unawaited(context.read<FirebirdConfigProvider>().loadConfigs());
  }

  Future<void> _showNewConfigDialog() async {
    final kind = await showDialog<DatabaseType>(
      context: context,
      builder: (BuildContext dialogContext) {
        return ContentDialog(
          title: Text(
            appLocaleString(
              context,
              'Tipo de banco de dados',
              'Database type',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  child: Text(
                    DatabaseTypeMetadata.of(DatabaseType.sqlServer).titleLabel,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(
                    DatabaseType.sqlServer,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  child: Text(
                    DatabaseTypeMetadata.of(DatabaseType.sybase).titleLabel,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(
                    DatabaseType.sybase,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  child: Text(
                    DatabaseTypeMetadata.of(DatabaseType.postgresql).titleLabel,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(
                    DatabaseType.postgresql,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  child: Text(
                    DatabaseTypeMetadata.of(DatabaseType.firebird).titleLabel,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(
                    DatabaseType.firebird,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            CancelButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
    if (!mounted || kind == null) {
      return;
    }
    switch (kind) {
      case DatabaseType.sqlServer:
        await _showConfigDialog(null);
      case DatabaseType.sybase:
        await _showSybaseConfigDialog(null);
      case DatabaseType.postgresql:
        await _showPostgresConfigDialog(null);
      case DatabaseType.firebird:
        await _showFirebirdConfigDialog(null);
    }
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

    return ScaffoldPage(
      header: PageHeader(
        title: Text(
          appLocaleString(
            context,
            'Configurações de banco de dados',
            'Database configuration',
          ),
        ),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: _refresh,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: Text(
                appLocaleString(
                  context,
                  'Nova configuração',
                  'New configuration',
                ),
              ),
              onPressed: _showNewConfigDialog,
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
        child: _DatabaseConfigsContent(
          sqlProvider: sqlProvider,
          sybaseProvider: sybaseProvider,
          postgresProvider: postgresProvider,
          firebirdProvider: firebirdProvider,
          onRefresh: _refresh,
          onAddConfig: _showNewConfigDialog,
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
      ),
    );
  }

  Future<void> _duplicateSqlServerConfig(SqlServerConfig config) async {
    final confirmed = await _confirmDuplicateConfiguration(config.name);
    if (!confirmed || !mounted) return;

    final provider = context.read<SqlServerConfigProvider>();
    final success = await provider.duplicateConfig(config);

    if (!mounted) return;

    if (success) {
      unawaited(
        MessageModal.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Configuração duplicada com sucesso!',
            'Configuration duplicated successfully!',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              provider.error ??
              appLocaleString(
                context,
                'Erro ao duplicar configuração',
                'Error duplicating configuration',
              ),
        ),
      );
    }
  }

  Future<void> _duplicateSybaseConfig(SybaseConfig config) async {
    final confirmed = await _confirmDuplicateConfiguration(config.name);
    if (!confirmed || !mounted) return;

    final provider = context.read<SybaseConfigProvider>();
    final success = await provider.duplicateConfig(config);

    if (!mounted) return;

    if (success) {
      unawaited(
        MessageModal.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Configuração duplicada com sucesso!',
            'Configuration duplicated successfully!',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              provider.error ??
              appLocaleString(
                context,
                'Erro ao duplicar configuração Sybase',
                'Error duplicating Sybase configuration',
              ),
        ),
      );
    }
  }

  Future<void> _showConfigDialog(SqlServerConfig? config) async {
    final result = await SqlServerConfigDialog.show(
      context,
      config: config,
    );

    if (result == null || !mounted) {
      return;
    }

    final sqlServerProvider = context.read<SqlServerConfigProvider>();
    final success = config == null
        ? await sqlServerProvider.createConfig(result)
        : await sqlServerProvider.updateConfig(result);
    final errorMessage = sqlServerProvider.error;

    if (!mounted) {
      return;
    }

    if (success) {
      unawaited(
        MessageModal.showSuccess(
          context,
          message: config == null
              ? appLocaleString(
                  context,
                  'Configuração criada com sucesso!',
                  'Configuration created successfully!',
                )
              : appLocaleString(
                  context,
                  'Configuração atualizada com sucesso!',
                  'Configuration updated successfully!',
                ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              errorMessage ??
              appLocaleString(
                context,
                'Erro ao salvar configuração',
                'Error saving configuration',
              ),
        ),
      );
    }
  }

  Future<void> _showSybaseConfigDialog(SybaseConfig? config) async {
    final result = await SybaseConfigDialog.show(
      context,
      config: config,
      backupService: GetIt.instance<ISybaseBackupService>(),
    );

    if (result != null && mounted) {
      final sybaseProvider = context.read<SybaseConfigProvider>();
      final success = config == null
          ? await sybaseProvider.createConfig(result)
          : await sybaseProvider.updateConfig(result);

      if (!mounted) return;

      if (success) {
        unawaited(
          MessageModal.showSuccess(
            context,
            message: config == null
                ? appLocaleString(
                    context,
                    'Configuração Sybase criada com sucesso!',
                    'Sybase configuration created successfully!',
                  )
                : appLocaleString(
                    context,
                    'Configuração Sybase atualizada com sucesso!',
                    'Sybase configuration updated successfully!',
                  ),
          ),
        );
      } else {
        unawaited(
          MessageModal.showError(
            context,
            message:
                sybaseProvider.error ??
                appLocaleString(
                  context,
                  'Erro ao salvar configuração Sybase',
                  'Error saving Sybase configuration',
                ),
          ),
        );
      }
    }
  }

  Future<void> _showPostgresConfigDialog(PostgresConfig? config) async {
    final result = await PostgresConfigDialog.show(
      context,
      config: config,
    );

    if (result != null && mounted) {
      final postgresProvider = context.read<PostgresConfigProvider>();
      final success = config == null
          ? await postgresProvider.createConfig(result)
          : await postgresProvider.updateConfig(result);

      if (!mounted) return;

      if (success) {
        unawaited(
          MessageModal.showSuccess(
            context,
            message: config == null
                ? appLocaleString(
                    context,
                    'Configuração PostgreSQL criada com sucesso!',
                    'PostgreSQL configuration created successfully!',
                  )
                : appLocaleString(
                    context,
                    'Configuração PostgreSQL atualizada com sucesso!',
                    'PostgreSQL configuration updated successfully!',
                  ),
          ),
        );
      } else {
        unawaited(
          MessageModal.showError(
            context,
            message:
                postgresProvider.error ??
                appLocaleString(
                  context,
                  'Erro ao salvar configuração PostgreSQL',
                  'Error saving PostgreSQL configuration',
                ),
          ),
        );
      }
    }
  }

  Future<void> _duplicatePostgresConfig(PostgresConfig config) async {
    final confirmed = await _confirmDuplicateConfiguration(config.name);
    if (!confirmed || !mounted) return;

    final provider = context.read<PostgresConfigProvider>();
    final success = await provider.duplicateConfig(config);

    if (!mounted) return;

    if (success) {
      unawaited(
        MessageModal.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Configuração duplicada com sucesso!',
            'Configuration duplicated successfully!',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              provider.error ??
              appLocaleString(
                context,
                'Erro ao duplicar configuração PostgreSQL',
                'Error duplicating PostgreSQL configuration',
              ),
        ),
      );
    }
  }

  Future<void> _confirmDeletePostgres(String id) async {
    final provider = context.read<PostgresConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ??
        appLocaleString(
          context,
          'Configuração PostgreSQL',
          'PostgreSQL configuration',
        );

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: DatabaseTypeMetadata.of(
        DatabaseType.postgresql,
      ).titleLabel,
      confirmMessage: appLocaleString(
        context,
        'Tem certeza que deseja excluir esta configuração?',
        'Are you sure you want to delete this configuration?',
      ),
      successMessage: appLocaleString(
        context,
        'Configuração PostgreSQL excluída com sucesso!',
        'PostgreSQL configuration deleted successfully!',
      ),
      fallbackErrorMessage: appLocaleString(
        context,
        'Erro ao excluir configuração PostgreSQL',
        'Error deleting PostgreSQL configuration',
      ),
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _showFirebirdConfigDialog(FirebirdConfig? config) async {
    final result = await FirebirdConfigDialog.show(
      context,
      config: config,
    );

    if (result != null && mounted) {
      final provider = context.read<FirebirdConfigProvider>();
      final success = config == null
          ? await provider.createConfig(result)
          : await provider.updateConfig(result);

      if (!mounted) {
        return;
      }

      if (success) {
        unawaited(
          MessageModal.showSuccess(
            context,
            message: config == null
                ? appLocaleString(
                    context,
                    'Configuração Firebird criada com sucesso!',
                    'Firebird configuration created successfully!',
                  )
                : appLocaleString(
                    context,
                    'Configuração Firebird atualizada com sucesso!',
                    'Firebird configuration updated successfully!',
                  ),
          ),
        );
      } else {
        unawaited(
          MessageModal.showError(
            context,
            message:
                provider.error ??
                appLocaleString(
                  context,
                  'Erro ao salvar configuração Firebird',
                  'Error saving Firebird configuration',
                ),
          ),
        );
      }
    }
  }

  Future<void> _duplicateFirebirdConfig(FirebirdConfig config) async {
    final confirmed = await _confirmDuplicateConfiguration(config.name);
    if (!confirmed || !mounted) {
      return;
    }

    final provider = context.read<FirebirdConfigProvider>();
    final success = await provider.duplicateConfig(config);

    if (!mounted) {
      return;
    }

    if (success) {
      unawaited(
        MessageModal.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Configuração duplicada com sucesso!',
            'Configuration duplicated successfully!',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              provider.error ??
              appLocaleString(
                context,
                'Erro ao duplicar configuração Firebird',
                'Error duplicating Firebird configuration',
              ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteFirebird(String id) async {
    final provider = context.read<FirebirdConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ??
        appLocaleString(
          context,
          'Configuração Firebird',
          'Firebird configuration',
        );

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: DatabaseTypeMetadata.of(DatabaseType.firebird).titleLabel,
      confirmMessage: appLocaleString(
        context,
        'Tem certeza que deseja excluir esta configuração?',
        'Are you sure you want to delete this configuration?',
      ),
      successMessage: appLocaleString(
        context,
        'Configuração Firebird excluída com sucesso!',
        'Firebird configuration deleted successfully!',
      ),
      fallbackErrorMessage: appLocaleString(
        context,
        'Erro ao excluir configuração Firebird',
        'Error deleting Firebird configuration',
      ),
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _confirmDeleteSqlServer(String id) async {
    final provider = context.read<SqlServerConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ??
        appLocaleString(
          context,
          'Configuração SQL Server',
          'SQL Server configuration',
        );

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: DatabaseTypeMetadata.of(DatabaseType.sqlServer).titleLabel,
      confirmMessage: appLocaleString(
        context,
        'Tem certeza que deseja excluir esta configuração?',
        'Are you sure you want to delete this configuration?',
      ),
      successMessage: appLocaleString(
        context,
        'Configuração SQL Server excluída com sucesso!',
        'SQL Server configuration deleted successfully!',
      ),
      fallbackErrorMessage: appLocaleString(
        context,
        'Erro ao excluir configuração SQL Server',
        'Error deleting SQL Server configuration',
      ),
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _confirmDeleteSybase(String id) async {
    final provider = context.read<SybaseConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ??
        appLocaleString(context, 'Configuração Sybase', 'Sybase configuration');

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: DatabaseTypeMetadata.of(DatabaseType.sybase).titleLabel,
      confirmMessage: appLocaleString(
        context,
        'Tem certeza que deseja excluir esta configuração?',
        'Are you sure you want to delete this configuration?',
      ),
      successMessage: appLocaleString(
        context,
        'Configuração Sybase excluída com sucesso!',
        'Sybase configuration deleted successfully!',
      ),
      fallbackErrorMessage: appLocaleString(
        context,
        'Erro ao excluir configuração Sybase',
        'Error deleting Sybase configuration',
      ),
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _handleDeleteWithDependencies({
    required String configId,
    required String configName,
    required String databaseLabel,
    required String confirmMessage,
    required String successMessage,
    required String fallbackErrorMessage,
    required Future<bool> Function() onDelete,
    required String? Function() readError,
  }) async {
    final linkedSchedules = await context
        .read<SchedulerProvider>()
        .getSchedulesByDatabaseConfig(configId);

    if (!mounted) return;

    if (linkedSchedules == null) {
      await MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Não foi possível validar dependências da configuração. '
              'Tente novamente.',
          'Could not validate configuration dependencies. Please try again.',
        ),
      );
      return;
    }

    if (linkedSchedules.isNotEmpty) {
      final action = await DatabaseConfigDependencyDialog.show(
        context,
        databaseLabel: databaseLabel,
        configName: configName,
        schedules: linkedSchedules,
      );

      if (!mounted) return;

      if (action == DependencyDialogAction.goToSchedules) {
        context.go(RouteNames.schedules);
      }
      return;
    }

    final confirmed = await _confirmDeleteConfiguration(confirmMessage);

    if (!confirmed || !mounted) return;

    final success = await onDelete();

    if (!mounted) return;

    if (success) {
      await MessageModal.showSuccess(context, message: successMessage);
      return;
    }

    await MessageModal.showError(
      context,
      message: readError() ?? fallbackErrorMessage,
    );
  }

  Future<bool> _confirmDeleteConfiguration(String message) {
    return MessageModal.showConfirm(
      context,
      title: appLocaleString(context, 'Confirmar exclusão', 'Confirm deletion'),
      message: message,
      confirmLabel: appLocaleString(context, 'Excluir', 'Delete'),
      confirmIcon: FluentIcons.delete,
    );
  }

  Future<bool> _confirmDuplicateConfiguration(String configName) {
    return MessageModal.showConfirm(
      context,
      title: appLocaleString(
        context,
        'Duplicar configuração',
        'Duplicate configuration',
      ),
      message: appLocaleString(
        context,
        'Tem certeza que deseja duplicar "$configName"?',
        'Are you sure you want to duplicate "$configName"?',
      ),
      confirmLabel: appLocaleString(context, 'Duplicar', 'Duplicate'),
      confirmIcon: FluentIcons.copy,
    );
  }
}

class _DatabaseConfigsContent extends StatelessWidget {
  const _DatabaseConfigsContent({
    required this.sqlProvider,
    required this.sybaseProvider,
    required this.postgresProvider,
    required this.firebirdProvider,
    required this.onRefresh,
    required this.onAddConfig,
    required this.onEditSql,
    required this.onDuplicateSql,
    required this.onDeleteSql,
    required this.onToggleSqlEnabled,
    required this.onEditSybase,
    required this.onDuplicateSybase,
    required this.onDeleteSybase,
    required this.onToggleSybaseEnabled,
    required this.onEditPostgres,
    required this.onDuplicatePostgres,
    required this.onDeletePostgres,
    required this.onTogglePostgresEnabled,
    required this.onEditFirebird,
    required this.onDuplicateFirebird,
    required this.onDeleteFirebird,
    required this.onToggleFirebirdEnabled,
  });

  final SqlServerConfigProvider sqlProvider;
  final SybaseConfigProvider sybaseProvider;
  final PostgresConfigProvider postgresProvider;
  final FirebirdConfigProvider firebirdProvider;

  final VoidCallback onRefresh;
  final VoidCallback onAddConfig;

  final Future<void> Function(SqlServerConfig?) onEditSql;
  final Future<void> Function(SqlServerConfig) onDuplicateSql;
  final Future<void> Function(String) onDeleteSql;
  final void Function(String, bool) onToggleSqlEnabled;

  final Future<void> Function(SybaseConfig?) onEditSybase;
  final Future<void> Function(SybaseConfig) onDuplicateSybase;
  final Future<void> Function(String) onDeleteSybase;
  final void Function(String, bool) onToggleSybaseEnabled;

  final Future<void> Function(PostgresConfig?) onEditPostgres;
  final Future<void> Function(PostgresConfig) onDuplicatePostgres;
  final Future<void> Function(String) onDeletePostgres;
  final void Function(String, bool) onTogglePostgresEnabled;

  final Future<void> Function(FirebirdConfig?) onEditFirebird;
  final Future<void> Function(FirebirdConfig) onDuplicateFirebird;
  final Future<void> Function(String) onDeleteFirebird;
  final void Function(String, bool) onToggleFirebirdEnabled;

  @override
  Widget build(BuildContext context) {
    if (sqlProvider.isLoading ||
        sybaseProvider.isLoading ||
        postgresProvider.isLoading ||
        firebirdProvider.isLoading) {
      return const _LoadingState();
    }

    final errorMessage =
        sqlProvider.error ??
        sybaseProvider.error ??
        postgresProvider.error ??
        firebirdProvider.error;
    if (errorMessage != null) {
      return _ErrorState(
        errorMessage: errorMessage,
        onRetry: onRefresh,
      );
    }

    if (sqlProvider.configs.isEmpty &&
        sybaseProvider.configs.isEmpty &&
        postgresProvider.configs.isEmpty &&
        firebirdProvider.configs.isEmpty) {
      return _EmptyState(onAddConfig: onAddConfig);
    }

    final hasSql = sqlProvider.configs.isNotEmpty;
    final hasSybase = sybaseProvider.configs.isNotEmpty;
    final hasPostgres = postgresProvider.configs.isNotEmpty;
    final hasFirebird = firebirdProvider.configs.isNotEmpty;
    final visibleSections =
        (hasSql ? 1 : 0) +
        (hasSybase ? 1 : 0) +
        (hasPostgres ? 1 : 0) +
        (hasFirebird ? 1 : 0);

    if (visibleSections == 1) {
      if (hasSql) {
        return _SqlServerConfigSection(
          configs: sqlProvider.configs,
          onEdit: onEditSql,
          onDuplicate: onDuplicateSql,
          onDelete: onDeleteSql,
          onToggleEnabled: onToggleSqlEnabled,
          showHeader: false,
        );
      }

      if (hasSybase) {
        return _SybaseConfigSection(
          configs: sybaseProvider.configs,
          onEdit: onEditSybase,
          onDuplicate: onDuplicateSybase,
          onDelete: onDeleteSybase,
          onToggleEnabled: onToggleSybaseEnabled,
          showHeader: false,
        );
      }

      if (hasPostgres) {
        return _PostgresConfigSection(
          configs: postgresProvider.configs,
          onEdit: onEditPostgres,
          onDuplicate: onDuplicatePostgres,
          onDelete: onDeletePostgres,
          onToggleEnabled: onTogglePostgresEnabled,
          showHeader: false,
        );
      }

      return _FirebirdConfigSection(
        configs: firebirdProvider.configs,
        onEdit: onEditFirebird,
        onDuplicate: onDuplicateFirebird,
        onDelete: onDeleteFirebird,
        onToggleEnabled: onToggleFirebirdEnabled,
        showHeader: false,
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        if (hasSql) ...[
          _SqlServerConfigSection(
            configs: sqlProvider.configs,
            onEdit: onEditSql,
            onDuplicate: onDuplicateSql,
            onDelete: onDeleteSql,
            onToggleEnabled: onToggleSqlEnabled,
            showHeader: true,
          ),
          if (hasSybase || hasPostgres || hasFirebird)
            const SizedBox(height: 24),
        ],
        if (hasSybase) ...[
          _SybaseConfigSection(
            configs: sybaseProvider.configs,
            onEdit: onEditSybase,
            onDuplicate: onDuplicateSybase,
            onDelete: onDeleteSybase,
            onToggleEnabled: onToggleSybaseEnabled,
            showHeader: true,
          ),
          if (hasPostgres || hasFirebird) const SizedBox(height: 24),
        ],
        if (hasPostgres) ...[
          _PostgresConfigSection(
            configs: postgresProvider.configs,
            onEdit: onEditPostgres,
            onDuplicate: onDuplicatePostgres,
            onDelete: onDeletePostgres,
            onToggleEnabled: onTogglePostgresEnabled,
            showHeader: true,
          ),
          if (hasFirebird) const SizedBox(height: 24),
        ],
        if (hasFirebird)
          _FirebirdConfigSection(
            configs: firebirdProvider.configs,
            onEdit: onEditFirebird,
            onDuplicate: onDuplicateFirebird,
            onDelete: onDeleteFirebird,
            onToggleEnabled: onToggleFirebirdEnabled,
            showHeader: true,
          ),
      ],
    );
  }
}

class _SqlServerConfigSection extends StatelessWidget {
  const _SqlServerConfigSection({
    required this.configs,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleEnabled,
    required this.showHeader,
  });

  final List<SqlServerConfig> configs;
  final Future<void> Function(SqlServerConfig?) onEdit;
  final Future<void> Function(SqlServerConfig) onDuplicate;
  final Future<void> Function(String) onDelete;
  final void Function(String, bool) onToggleEnabled;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final list = SqlServerConfigList(
      configs: configs,
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      onToggleEnabled: onToggleEnabled,
    );

    if (!showHeader) {
      return list;
    }

    final activeCount = configs.where((c) => c.enabled).length;
    final inactiveCount = configs.where((c) => !c.enabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeaderWithStatusBadges(
          label: DatabaseTypeMetadata.of(DatabaseType.sqlServer).titleLabel,
          count: configs.length,
          activeCount: activeCount,
          inactiveCount: inactiveCount,
        ),
        const SizedBox(height: 8),
        list,
      ],
    );
  }
}

class _SybaseConfigSection extends StatelessWidget {
  const _SybaseConfigSection({
    required this.configs,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleEnabled,
    required this.showHeader,
  });

  final List<SybaseConfig> configs;
  final Future<void> Function(SybaseConfig?) onEdit;
  final Future<void> Function(SybaseConfig) onDuplicate;
  final Future<void> Function(String) onDelete;
  final void Function(String, bool) onToggleEnabled;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final list = SybaseConfigList(
      configs: configs,
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      onToggleEnabled: onToggleEnabled,
    );

    if (!showHeader) {
      return list;
    }

    final activeCount = configs.where((c) => c.enabled).length;
    final inactiveCount = configs.where((c) => !c.enabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeaderWithStatusBadges(
          label: DatabaseTypeMetadata.of(DatabaseType.sybase).titleLabel,
          count: configs.length,
          activeCount: activeCount,
          inactiveCount: inactiveCount,
        ),
        const SizedBox(height: 8),
        list,
      ],
    );
  }
}

class _PostgresConfigSection extends StatelessWidget {
  const _PostgresConfigSection({
    required this.configs,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleEnabled,
    required this.showHeader,
  });

  final List<PostgresConfig> configs;
  final Future<void> Function(PostgresConfig?) onEdit;
  final Future<void> Function(PostgresConfig) onDuplicate;
  final Future<void> Function(String) onDelete;
  final void Function(String, bool) onToggleEnabled;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final grid = PostgresConfigGrid(
      configs: configs,
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      onToggleEnabled: onToggleEnabled,
    );

    if (!showHeader) {
      return grid;
    }

    final activeCount = configs.where((c) => c.enabled).length;
    final inactiveCount = configs.where((c) => !c.enabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeaderWithStatusBadges(
          label: DatabaseTypeMetadata.of(DatabaseType.postgresql).titleLabel,
          count: configs.length,
          activeCount: activeCount,
          inactiveCount: inactiveCount,
        ),
        const SizedBox(height: 8),
        grid,
      ],
    );
  }
}

class _FirebirdConfigSection extends StatelessWidget {
  const _FirebirdConfigSection({
    required this.configs,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleEnabled,
    required this.showHeader,
  });

  final List<FirebirdConfig> configs;
  final Future<void> Function(FirebirdConfig?) onEdit;
  final Future<void> Function(FirebirdConfig) onDuplicate;
  final Future<void> Function(String) onDelete;
  final void Function(String, bool) onToggleEnabled;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final grid = FirebirdConfigGrid(
      configs: configs,
      onEdit: onEdit,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      onToggleEnabled: onToggleEnabled,
    );

    if (!showHeader) {
      return grid;
    }

    final activeCount = configs.where((c) => c.enabled).length;
    final inactiveCount = configs.where((c) => !c.enabled).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeaderWithStatusBadges(
          label: DatabaseTypeMetadata.of(DatabaseType.firebird).titleLabel,
          count: configs.length,
          activeCount: activeCount,
          inactiveCount: inactiveCount,
        ),
        const SizedBox(height: 8),
        grid,
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(64),
        child: ProgressRing(),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.errorMessage,
    required this.onRetry,
  });

  final String errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error,
              size: 64,
              color: context.appSemanticColors.danger,
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage,
              style: FluentTheme.of(context).typography.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Button(
              onPressed: onRetry,
              child: Text(
                appLocaleString(context, 'Tentar novamente', 'Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onAddConfig,
  });

  final VoidCallback onAddConfig;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(64),
      child: EmptyState(
        icon: FluentIcons.database,
        message: appLocaleString(
          context,
          'Nenhuma configuração de banco de dados cadastrada',
          'No database configuration registered',
        ),
        actionLabel: appLocaleString(
          context,
          'Adicionar configuração',
          'Add configuration',
        ),
        onAction: onAddConfig,
      ),
    );
  }
}
