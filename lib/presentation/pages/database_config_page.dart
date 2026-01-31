import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/sql_server/sql_server.dart';
import 'package:backup_database/presentation/widgets/sybase/sybase.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:get_it/get_it.dart';
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
      context.read<SqlServerConfigProvider>().loadConfigs();
      context.read<SybaseConfigProvider>().loadConfigs();
    });
  }

  void _refresh() {
    context.read<SqlServerConfigProvider>().loadConfigs();
    context.read<SybaseConfigProvider>().loadConfigs();
    context.read<PostgresConfigProvider>().loadConfigs();
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: () => _showConfigDialog(null),
            ),
          ],
        ),
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer<SqlServerConfigProvider>(
              builder: (context, sqlProvider, child) {
                return Consumer<SybaseConfigProvider>(
                  builder: (context, sybaseProvider, child) {
                    return Consumer<PostgresConfigProvider>(
                      builder: (context, postgresProvider, child) {
                        final isLoading =
                            sqlProvider.isLoading ||
                            sybaseProvider.isLoading ||
                            postgresProvider.isLoading;
                        final hasError =
                            sqlProvider.error != null ||
                            sybaseProvider.error != null ||
                            postgresProvider.error != null;
                        final isEmpty =
                            sqlProvider.configs.isEmpty &&
                            sybaseProvider.configs.isEmpty &&
                            postgresProvider.configs.isEmpty;

                        if (isLoading) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(64),
                              child: ProgressRing(),
                            ),
                          );
                        }

                        if (hasError) {
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
                                    sqlProvider.error ??
                                        sybaseProvider.error ??
                                        postgresProvider.error ??
                                        'Erro desconhecido',
                                    style: FluentTheme.of(
                                      context,
                                    ).typography.bodyLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  Button(
                                    onPressed: _refresh,
                                    child: const Text('Tentar Novamente'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        if (isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(64),
                            child: EmptyState(
                              icon: FluentIcons.database,
                              message:
                                  'Nenhuma configuração de banco de dados cadastrada',
                              actionLabel: 'Adicionar Configuração',
                              onAction: () => _showConfigDialog(null),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (sqlProvider.configs.isNotEmpty) ...[
                              Text(
                                'SQL Server',
                                style: FluentTheme.of(context)
                                    .typography
                                    .subtitle
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              SqlServerConfigList(
                                configs: sqlProvider.configs,
                                onEdit: _showConfigDialog,
                                onDuplicate: _duplicateSqlServerConfig,
                                onDelete: _confirmDeleteSqlServer,
                                onToggleEnabled: (id, enabled) =>
                                    sqlProvider.toggleEnabled(id, enabled),
                              ),
                              const SizedBox(height: 24),
                            ],

                            if (sybaseProvider.configs.isNotEmpty) ...[
                              Text(
                                'Sybase SQL Anywhere',
                                style: FluentTheme.of(context)
                                    .typography
                                    .subtitle
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              SybaseConfigList(
                                configs: sybaseProvider.configs,
                                onEdit: _showSybaseConfigDialog,
                                onDuplicate: _duplicateSybaseConfig,
                                onDelete: _confirmDeleteSybase,
                                onToggleEnabled: (id, enabled) =>
                                    sybaseProvider.toggleEnabled(id, enabled),
                              ),
                              const SizedBox(height: 24),
                            ],

                            if (postgresProvider.configs.isNotEmpty) ...[
                              Text(
                                'PostgreSQL',
                                style: FluentTheme.of(context)
                                    .typography
                                    .subtitle
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              _buildPostgresConfigList(
                                postgresProvider.configs,
                                onEdit: _showPostgresConfigDialog,
                                onDuplicate: _duplicatePostgresConfig,
                                onDelete: _confirmDeletePostgres,
                                onToggleEnabled: (id, enabled) =>
                                    postgresProvider.toggleEnabled(id, enabled),
                              ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _duplicateSqlServerConfig(SqlServerConfig config) async {
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
    // Converter PostgresConfig para SqlServerConfig temporariamente para usar o diálogo genérico
    SqlServerConfig? tempConfig;
    if (config != null) {
      tempConfig = SqlServerConfig(
        id: config.id,
        name: config.name,
        server: config.host, // Usar host como server temporariamente
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
        return; // Se não for PostgresConfig, não processar
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta configuração PostgreSQL?',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      final provider = context.read<PostgresConfigProvider>();
      final success = await provider.deleteConfig(id);

      if (!mounted) return;

      if (success) {
        MessageModal.showSuccess(
          context,
          message: 'Configuração PostgreSQL excluída com sucesso!',
        );
      } else {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao excluir configuração PostgreSQL',
        );
      }
    }
  }

  Future<void> _confirmDeleteSqlServer(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta configuração SQL Server?',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      final provider = context.read<SqlServerConfigProvider>();
      final success = await provider.deleteConfig(id);

      if (!mounted) return;

      if (success) {
        MessageModal.showSuccess(
          context,
          message: 'Configuração SQL Server excluída com sucesso!',
        );
      } else {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao excluir configuração',
        );
      }
    }
  }

  Future<void> _confirmDeleteSybase(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta configuração Sybase?',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      final provider = context.read<SybaseConfigProvider>();
      final success = await provider.deleteConfig(id);

      if (!mounted) return;

      if (success) {
        MessageModal.showSuccess(
          context,
          message: 'Configuração Sybase excluída com sucesso!',
        );
      } else {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao excluir configuração Sybase',
        );
      }
    }
  }

  Widget _buildPostgresConfigList(
    List<PostgresConfig> configs, {
    Function(PostgresConfig)? onEdit,
    Function(PostgresConfig)? onDuplicate,
    Function(String)? onDelete,
    Function(String, bool)? onToggleEnabled,
  }) {
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
        return ConfigListItem(
          name: config.name,
          icon: FluentIcons.database,
          enabled: config.enabled,
          onToggleEnabled: onToggleEnabled != null
              ? (enabled) => onToggleEnabled(config.id, enabled)
              : null,
          onEdit: onEdit != null ? () => onEdit(config) : null,
          onDuplicate: onDuplicate != null ? () => onDuplicate(config) : null,
          onDelete: onDelete != null ? () => onDelete(config.id) : null,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text('${config.host}:${config.port}'),
              const SizedBox(height: 2),
              Text('Banco: ${config.database}'),
              const SizedBox(height: 2),
              Text('Usuário: ${config.username}'),
            ],
          ),
        );
      },
    );
  }
}
