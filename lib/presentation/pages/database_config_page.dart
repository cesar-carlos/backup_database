import 'package:flutter/material.dart';
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
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Configurações de Banco de Dados',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                  tooltip: 'Atualizar',
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Nova Configuração',
                  icon: Icons.add,
                  onPressed: () => _showConfigDialog(context, null),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // SQL Server Configs
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
                          child: CircularProgressIndicator(),
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
                                Icons.error_outline,
                                size: 64,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                sqlProvider.error ??
                                    sybaseProvider.error ??
                                    'Erro desconhecido',
                                style: Theme.of(context).textTheme.bodyLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
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
                          icon: Icons.storage_outlined,
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
                        // SQL Server Configs
                        if (sqlProvider.configs.isNotEmpty) ...[
                          Text(
                            'SQL Server',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
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

                        // Sybase Configs
                        if (sybaseProvider.configs.isNotEmpty) ...[
                          Text(
                            'Sybase SQL Anywhere',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
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

      // Verificar o tipo retornado e salvar no provider correto
      if (result is SybaseConfig) {
        // Configuração Sybase - salvar no SybaseConfigProvider
        final sybaseProvider = context.read<SybaseConfigProvider>();
        success = config == null
            ? await sybaseProvider.createConfig(result)
            : await sybaseProvider.updateConfig(result);
        errorMessage = sybaseProvider.error;
      } else if (result is SqlServerConfig) {
        // Configuração SQL Server - salvar no SqlServerConfigProvider
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
        ErrorModal.show(
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
        ErrorModal.show(
          context,
          message: sybaseProvider.error ?? 'Erro ao salvar configuração Sybase',
        );
      }
    }
  }

  Future<void> _confirmDeleteSqlServer(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta configuração SQL Server?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.delete,
              foregroundColor: AppColors.buttonTextOnColored,
            ),
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
        ErrorModal.show(
          context,
          message: provider.error ?? 'Erro ao excluir configuração',
        );
      }
    }
  }

  Future<void> _confirmDeleteSybase(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta configuração Sybase?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.delete,
              foregroundColor: AppColors.buttonTextOnColored,
            ),
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
        ErrorModal.show(
          context,
          message: provider.error ?? 'Erro ao excluir configuração Sybase',
        );
      }
    }
  }
}
