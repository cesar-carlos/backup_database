import 'dart:async';

import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/sybase/sybase.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class SybaseConfigPage extends StatefulWidget {
  const SybaseConfigPage({super.key});

  @override
  State<SybaseConfigPage> createState() => _SybaseConfigPageState();
}

class _SybaseConfigPageState extends State<SybaseConfigPage> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Configurações do Sybase'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: () {
                unawaited(
                  context.read<SybaseConfigProvider>().loadConfigs(),
                );
              },
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('Nova Configuração'),
              onPressed: () => _showConfigDialog(null),
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer<SybaseConfigProvider>(
              builder: (context, provider, _) => SybaseToolsStatusCard(
                status: provider.toolsStatus,
                isLoading: provider.isLoadingTools,
                onRefresh: provider.refreshToolsStatus,
              ),
            ),
            const SizedBox(height: 16),
            const SybaseBackupHealthCard(),
            const SizedBox(height: 24),
            Expanded(
              child: Consumer<SybaseConfigProvider>(
                builder: (context, provider, child) {
                  if (provider.isLoading) {
                    return const Center(child: ProgressRing());
                  }

                  if (provider.error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            FluentIcons.error,
                            size: 64,
                            color: context.colors.danger,
                          ),
                          const SizedBox(height: 16),
                          SelectableText.rich(
                            TextSpan(
                              text: provider.error,
                              style: FluentTheme.of(context)
                                  .typography
                                  .bodyLarge
                                  ?.copyWith(color: context.colors.danger),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Button(
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
                        icon: FluentIcons.database,
                        message: 'Nenhuma configuração de Sybase cadastrada',
                        actionLabel: 'Adicionar Configuração',
                        onAction: () => _showConfigDialog(null),
                      ),
                    );
                  }

                  return SybaseConfigList(
                    configs: provider.configs,
                    onEdit: _showConfigDialog,
                    onDuplicate: _duplicateConfig,
                    onDelete: _confirmDelete,
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

  Future<void> _showConfigDialog(SybaseConfig? config) async {
    final result = await SybaseConfigDialog.show(
      context,
      config: config,
    );

    if (!mounted) return;

    if (result != null) {
      final provider = context.read<SybaseConfigProvider>();
      final success = config == null
          ? await provider.createConfig(result)
          : await provider.updateConfig(result);

      if (!mounted) return;

      if (success) {
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: config == null
                ? 'Configuração criada com sucesso!'
                : 'Configuração atualizada com sucesso!',
          ),
        );
      } else {
        unawaited(
          MessageModal.showError(
            context,
            message: provider.error ?? 'Erro ao salvar configuração',
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(String id) async {
    if (!mounted) return;
    final provider = context.read<SybaseConfigProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta configuração? Esta ação não pode ser desfeita.',
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

    if (confirmed ?? false) {
      if (!mounted) return;

      final success = await provider.deleteConfig(id);

      if (!mounted) return;

      if (success) {
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: 'Configuração excluída com sucesso!',
          ),
        );
      } else {
        unawaited(
          MessageModal.showError(
            context,
            message: provider.error ?? 'Erro ao excluir configuração',
          ),
        );
      }
    }
  }

  Future<void> _duplicateConfig(SybaseConfig config) async {
    final provider = context.read<SybaseConfigProvider>();
    final success = await provider.duplicateConfig(config);

    if (!mounted) return;

    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: 'Configuração duplicada com sucesso!',
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao duplicar configuração',
        ),
      );
    }
  }
}
