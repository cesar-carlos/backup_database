import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/scheduler_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/postgres/postgres.dart';
import 'package:backup_database/presentation/widgets/sql_server/sql_server.dart';
import 'package:backup_database/presentation/widgets/sybase/sybase.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: FluentTheme.of(context).typography.subtitle,
        ),
        const SizedBox(width: 8),
        Text(
          '($count)',
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}

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
      context.read<SqlServerConfigProvider>().loadConfigs();
      context.read<SybaseConfigProvider>().loadConfigs();
    });
  }

  void _refresh() {
    context.read<SqlServerConfigProvider>().loadConfigs();
    context.read<SybaseConfigProvider>().loadConfigs();
    context.read<PostgresConfigProvider>().loadConfigs();
  }

  void _showNewConfigDialog() {
    _showConfigDialog(null);
  }

  void _toggleSqlServerEnabled(String id, bool enabled) {
    context.read<SqlServerConfigProvider>().toggleEnabled(id, enabled);
  }

  void _toggleSybaseEnabled(String id, bool enabled) {
    context.read<SybaseConfigProvider>().toggleEnabled(id, enabled);
  }

  void _togglePostgresEnabled(String id, bool enabled) {
    context.read<PostgresConfigProvider>().toggleEnabled(id, enabled);
  }

  @override
  Widget build(BuildContext context) {
    final sqlProvider = context.watch<SqlServerConfigProvider>();
    final sybaseProvider = context.watch<SybaseConfigProvider>();
    final postgresProvider = context.watch<PostgresConfigProvider>();

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Configurações de Banco de Dados'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: _refresh,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('Nova Configuração'),
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
        ),
      ),
    );
  }

  Future<void> _duplicateSqlServerConfig(SqlServerConfig config) async {
    final confirmed = await _showDuplicateConfirmDialog(config.name);
    if (!confirmed || !mounted) return;

    final provider = context.read<SqlServerConfigProvider>();
    final success = await provider.duplicateConfig(config);

    if (!mounted) return;

    if (success) {
      MessageModal.showSuccess(
        context,
        message: 'Configuração duplicada com sucesso!',
      );
    } else {
      MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao duplicar configuração',
      );
    }
  }

  Future<void> _duplicateSybaseConfig(SybaseConfig config) async {
    final confirmed = await _showDuplicateConfirmDialog(config.name);
    if (!confirmed || !mounted) return;

    final provider = context.read<SybaseConfigProvider>();
    final success = await provider.duplicateConfig(config);

    if (!mounted) return;

    if (success) {
      MessageModal.showSuccess(
        context,
        message: 'Configuração duplicada com sucesso!',
      );
    } else {
      MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao duplicar configuração Sybase',
      );
    }
  }

  Future<void> _showConfigDialog(SqlServerConfig? config) async {
    final result = await SqlServerConfigDialog.show(context, config: config);

    if (result != null && mounted) {
      var success = false;
      String? errorMessage;

      if (result is SybaseConfig) {
        final sybaseProvider = context.read<SybaseConfigProvider>();
        success = config == null
            ? await sybaseProvider.createConfig(result)
            : await sybaseProvider.updateConfig(result);
        errorMessage = sybaseProvider.error;
      } else if (result is SqlServerConfig) {
        final sqlServerProvider = context.read<SqlServerConfigProvider>();
        success = config == null
            ? await sqlServerProvider.createConfig(result)
            : await sqlServerProvider.updateConfig(result);
        errorMessage = sqlServerProvider.error;
      } else if (result is PostgresConfig) {
        final postgresProvider = context.read<PostgresConfigProvider>();
        success = config == null
            ? await postgresProvider.createConfig(result)
            : await postgresProvider.updateConfig(result);
        errorMessage = postgresProvider.error;
      }

      if (!mounted) return;

      if (success) {
        MessageModal.showSuccess(
          context,
          message: config == null
              ? 'Configuração criada com sucesso!'
              : 'Configuração atualizada com sucesso!',
        );
      } else {
        MessageModal.showError(
          context,
          message: errorMessage ?? 'Erro ao salvar configuração',
        );
      }
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
        MessageModal.showSuccess(
          context,
          message: config == null
              ? 'Configuração Sybase criada com sucesso!'
              : 'Configuração Sybase atualizada com sucesso!',
        );
      } else {
        MessageModal.showError(
          context,
          message: sybaseProvider.error ?? 'Erro ao salvar configuração Sybase',
        );
      }
    }
  }

  Future<void> _showPostgresConfigDialog(PostgresConfig? config) async {
    SqlServerConfig? tempConfig;
    if (config != null) {
      tempConfig = SqlServerConfig(
        id: config.id,
        name: config.name,
        server: config.host,
        port: config.port,
        database: config.database,
        username: config.username,
        password: config.password,
        enabled: config.enabled,
        createdAt: config.createdAt,
        updatedAt: config.updatedAt,
      );
    }

    final result = await SqlServerConfigDialog.show(
      context,
      config: tempConfig,
      initialType: DatabaseType.postgresql,
    );

    if (result != null && mounted) {
      if (result is! PostgresConfig) {
        return;
      }

      final postgresConfig = result;
      final postgresProvider = context.read<PostgresConfigProvider>();
      final success = config == null
          ? await postgresProvider.createConfig(postgresConfig)
          : await postgresProvider.updateConfig(postgresConfig);

      if (!mounted) return;

      if (success) {
        MessageModal.showSuccess(
          context,
          message: config == null
              ? 'Configuração PostgreSQL criada com sucesso!'
              : 'Configuração PostgreSQL atualizada com sucesso!',
        );
      } else {
        MessageModal.showError(
          context,
          message:
              postgresProvider.error ??
              'Erro ao salvar configuração PostgreSQL',
        );
      }
    }
  }

  Future<void> _duplicatePostgresConfig(PostgresConfig config) async {
    final confirmed = await _showDuplicateConfirmDialog(config.name);
    if (!confirmed || !mounted) return;

    final provider = context.read<PostgresConfigProvider>();
    final success = await provider.duplicateConfig(config);

    if (!mounted) return;

    if (success) {
      MessageModal.showSuccess(
        context,
        message: 'Configuração duplicada com sucesso!',
      );
    } else {
      MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao duplicar configuração PostgreSQL',
      );
    }
  }

  Future<void> _confirmDeletePostgres(String id) async {
    final provider = context.read<PostgresConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ?? 'Configuração PostgreSQL';

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: 'PostgreSQL',
      confirmMessage: 'Tem certeza que deseja excluir esta configuração?',
      successMessage: 'Configuração PostgreSQL excluída com sucesso!',
      fallbackErrorMessage: 'Erro ao excluir configuração PostgreSQL',
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _confirmDeleteSqlServer(String id) async {
    final provider = context.read<SqlServerConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ?? 'Configuração SQL Server';

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: 'SQL Server',
      confirmMessage: 'Tem certeza que deseja excluir esta configuração?',
      successMessage: 'Configuração SQL Server excluída com sucesso!',
      fallbackErrorMessage: 'Erro ao excluir configuração SQL Server',
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _confirmDeleteSybase(String id) async {
    final provider = context.read<SybaseConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ?? 'Configuração Sybase';

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: 'Sybase SQL Anywhere',
      confirmMessage: 'Tem certeza que deseja excluir esta configuração?',
      successMessage: 'Configuração Sybase excluída com sucesso!',
      fallbackErrorMessage: 'Erro ao excluir configuração Sybase',
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
        message:
            'Não foi possível validar dependências da configuração. '
            'Tente novamente.',
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

    final confirmed = await _showDeleteConfirmDialog(confirmMessage);

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

  Future<bool> _showDeleteConfirmDialog(String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(message),
        actions: [
          CancelButton(onPressed: () => Navigator.of(context).pop(false)),
          ActionButton(
            label: 'Excluir',
            icon: FluentIcons.delete,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<bool> _showDuplicateConfirmDialog(String configName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Duplicar Configuração'),
        content: Text('Tem certeza que deseja duplicar "$configName"?'),
        actions: [
          CancelButton(onPressed: () => Navigator.of(context).pop(false)),
          ActionButton(
            label: 'Duplicar',
            icon: FluentIcons.copy,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }
}

class _DatabaseConfigsContent extends StatelessWidget {
  const _DatabaseConfigsContent({
    required this.sqlProvider,
    required this.sybaseProvider,
    required this.postgresProvider,
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
  });

  final SqlServerConfigProvider sqlProvider;
  final SybaseConfigProvider sybaseProvider;
  final PostgresConfigProvider postgresProvider;

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

  @override
  Widget build(BuildContext context) {
    if (sqlProvider.isLoading ||
        sybaseProvider.isLoading ||
        postgresProvider.isLoading) {
      return const _LoadingState();
    }

    final errorMessage =
        sqlProvider.error ?? sybaseProvider.error ?? postgresProvider.error;
    if (errorMessage != null) {
      return _ErrorState(
        errorMessage: errorMessage,
        onRetry: onRefresh,
      );
    }

    if (sqlProvider.configs.isEmpty &&
        sybaseProvider.configs.isEmpty &&
        postgresProvider.configs.isEmpty) {
      return _EmptyState(onAddConfig: onAddConfig);
    }

    final hasSql = sqlProvider.configs.isNotEmpty;
    final hasSybase = sybaseProvider.configs.isNotEmpty;
    final hasPostgres = postgresProvider.configs.isNotEmpty;
    final visibleSections =
        (hasSql ? 1 : 0) + (hasSybase ? 1 : 0) + (hasPostgres ? 1 : 0);

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

      return _PostgresConfigSection(
        configs: postgresProvider.configs,
        onEdit: onEditPostgres,
        onDuplicate: onDuplicatePostgres,
        onDelete: onDeletePostgres,
        onToggleEnabled: onTogglePostgresEnabled,
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
          if (hasSybase || hasPostgres) const SizedBox(height: 24),
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
          if (hasPostgres) const SizedBox(height: 24),
        ],
        if (hasPostgres)
          _PostgresConfigSection(
            configs: postgresProvider.configs,
            onEdit: onEditPostgres,
            onDuplicate: onDuplicatePostgres,
            onDelete: onDeletePostgres,
            onToggleEnabled: onTogglePostgresEnabled,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'SQL Server',
          count: configs.length,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'Sybase SQL Anywhere',
          count: configs.length,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'PostgreSQL',
          count: configs.length,
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
            const Icon(
              FluentIcons.error,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage,
              style: FluentTheme.of(context).typography.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Button(onPressed: onRetry, child: const Text('Tentar Novamente')),
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
        message: 'Nenhuma configuração de banco de dados cadastrada',
        actionLabel: 'Adicionar Configuração',
        onAction: onAddConfig,
      ),
    );
  }
}
