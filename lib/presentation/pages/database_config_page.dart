import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../application/providers/sql_server_config_provider.dart';
import '../../application/providers/sybase_config_provider.dart';
import '../../domain/entities/sql_server_config.dart';
import '../../domain/entities/sybase_config.dart';
import '../widgets/common/common.dart';
import '../widgets/sql_server/sql_server.dart';
import '../widgets/sybase/sybase.dart';

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
              onPressed: () => _showConfigDialog(context, null),
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
                    final isLoading =
                        sqlProvider.isLoading || sybaseProvider.isLoading;
                    final hasError =
                        sqlProvider.error != null ||
                        sybaseProvider.error != null;
                    final isEmpty =
                        sqlProvider.configs.isEmpty &&
                        sybaseProvider.configs.isEmpty;

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
                              Icon(
                                FluentIcons.error,
                                size: 64,
                                color: AppColors.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                sqlProvider.error ??
                                    sybaseProvider.error ??
                                    'Erro desconhecido',
                                style: FluentTheme.of(context).typography.bodyLarge,
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
                          onAction: () => _showConfigDialog(context, null),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (sqlProvider.configs.isNotEmpty) ...[
                          Text(
                            'SQL Server',
                            style: FluentTheme.of(context).typography.subtitle?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          SqlServerConfigList(
                            configs: sqlProvider.configs,
                            onEdit: (config) =>
                                _showConfigDialog(context, config),
                            onDelete: (id) =>
                                _confirmDeleteSqlServer(context, id),
                            onToggleEnabled: (id, enabled) =>
                                sqlProvider.toggleEnabled(id, enabled),
                          ),
                          const SizedBox(height: 24),
                        ],

                        if (sybaseProvider.configs.isNotEmpty) ...[
                          Text(
                            'Sybase SQL Anywhere',
                            style: FluentTheme.of(context).typography.subtitle?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 12),
                          SybaseConfigList(
                            configs: sybaseProvider.configs,
                            onEdit: (config) =>
                                _showSybaseConfigDialog(context, config),
                            onDelete: (id) => _confirmDeleteSybase(context, id),
                            onToggleEnabled: (id, enabled) =>
                                sybaseProvider.toggleEnabled(id, enabled),
                          ),
                        ],
                      ],
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

  Future<void> _showConfigDialog(
    BuildContext context,
    SqlServerConfig? config,
  ) async {
    final result = await SqlServerConfigDialog.show(context, config: config);

    if (result != null && mounted) {
      bool success = false;
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

  Future<void> _showSybaseConfigDialog(
    BuildContext context,
    SybaseConfig? config,
  ) async {
    final result = await SybaseConfigDialog.show(context, config: config);

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

  Future<void> _confirmDeleteSqlServer(BuildContext context, String id) async {
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

    if (confirmed == true && mounted) {
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

  Future<void> _confirmDeleteSybase(BuildContext context, String id) async {
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

    if (confirmed == true && mounted) {
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
}
