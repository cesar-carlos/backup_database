import 'dart:async';

import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/sql_server/sql_server.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class SqlServerConfigPage extends StatefulWidget {
  const SqlServerConfigPage({super.key});

  @override
  State<SqlServerConfigPage> createState() => _SqlServerConfigPageState();
}

class _SqlServerConfigPageState extends State<SqlServerConfigPage> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Configurações do SQL Server'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: () {
                unawaited(
                  context.read<SqlServerConfigProvider>().loadConfigs(),
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
            Expanded(
              child: Consumer<SqlServerConfigProvider>(
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
                        message:
                            'Nenhuma configuração de SQL Server cadastrada',
                        actionLabel: 'Adicionar Configuração',
                        onAction: () => _showConfigDialog(null),
                      ),
                    );
                  }

                  return SqlServerConfigList(
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
          message: errorMessage ?? 'Erro ao salvar configuração',
        ),
      );
    }
  }

  Future<void> _confirmDelete(String id) async {
    if (!mounted) return;
    final provider = context.read<SqlServerConfigProvider>();

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

  Future<void> _duplicateConfig(SqlServerConfig config) async {
    final provider = context.read<SqlServerConfigProvider>();
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
