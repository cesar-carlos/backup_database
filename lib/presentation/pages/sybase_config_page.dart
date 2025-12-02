import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../application/providers/sybase_config_provider.dart';
import '../../domain/entities/sybase_config.dart';
import '../widgets/common/common.dart';
import '../widgets/sybase/sybase.dart';

class SybaseConfigPage extends StatefulWidget {
  const SybaseConfigPage({super.key});

  @override
  State<SybaseConfigPage> createState() => _SybaseConfigPageState();
}

class _SybaseConfigPageState extends State<SybaseConfigPage> {
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
                  'Configurações do Sybase',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    context.read<SybaseConfigProvider>().loadConfigs();
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
              child: Consumer<SybaseConfigProvider>(
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
                        icon: Icons.dns_outlined,
                        message: 'Nenhuma configuração de Sybase cadastrada',
                        actionLabel: 'Adicionar Configuração',
                        onAction: () => _showConfigDialog(context, null),
                      ),
                    );
                  }

                  return SybaseConfigList(
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
    SybaseConfig? config,
  ) async {
    final result = await SybaseConfigDialog.show(context, config: config);

    if (result != null && mounted) {
      final provider = context.read<SybaseConfigProvider>();
      final success = config == null
          ? await provider.createConfig(result)
          : await provider.updateConfig(result);

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
          message: provider.error ?? 'Erro ao salvar configuração',
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    if (!mounted) return;
    final provider = context.read<SybaseConfigProvider>();

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
