import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../application/providers/sql_server_config_provider.dart';
import '../../application/providers/sybase_config_provider.dart';
import '../../domain/entities/sql_server_config.dart';
import '../../domain/entities/sybase_config.dart';
import '../widgets/common/common.dart';
import '../widgets/sql_server/sql_server.dart';

class SqlServerConfigPage extends StatefulWidget {
  const SqlServerConfigPage({super.key});

  @override
  State<SqlServerConfigPage> createState() => _SqlServerConfigPageState();
}

class _SqlServerConfigPageState extends State<SqlServerConfigPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Configurações do SQL Server',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    context.read<SqlServerConfigProvider>().loadConfigs();
                  },
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
            Expanded(
              child: Consumer<SqlServerConfigProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (provider.error != null) {
                    return Center(
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
                            provider.error!,
                            style: Theme.of(context).textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => provider.loadConfigs(),
                            child: const Text('Tentar Novamente'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (provider.configs.isEmpty) {
                    return AppCard(
                      child: EmptyState(
                        icon: Icons.storage_outlined,
                        message:
                            'Nenhuma configuração de SQL Server cadastrada',
                        actionLabel: 'Adicionar Configuração',
                        onAction: () => _showConfigDialog(context, null),
                      ),
                    );
                  }

                  return SqlServerConfigList(
                    configs: provider.configs,
                    onEdit: (config) => _showConfigDialog(context, config),
                    onDelete: (id) => _confirmDelete(context, id),
                    onToggleEnabled: (id, enabled) =>
                        provider.toggleEnabled(id, enabled),
                  );
                },
              ),
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

  Future<void> _confirmDelete(BuildContext context, String id) async {
    if (!mounted) return;
    final provider = context.read<SqlServerConfigProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta configuração? Esta ação não pode ser desfeita.',
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

    if (confirmed == true) {
      if (!mounted) return;

      final success = await provider.deleteConfig(id);

      if (!mounted) return;

      if (success) {
        MessageModal.showSuccess(
          context,
          message: 'Configuração excluída com sucesso!',
        );
      } else {
        ErrorModal.show(
          context,
          message: provider.error ?? 'Erro ao excluir configuração',
        );
      }
    }
  }
}
