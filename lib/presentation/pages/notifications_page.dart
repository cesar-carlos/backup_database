import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/notifications/notifications.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

bool _hasEmailNotificationFeature(LicenseProvider licenseProvider) {
  final license = licenseProvider.currentLicense;
  return licenseProvider.hasValidLicense &&
      (license?.hasFeature(LicenseFeatures.emailNotification) ?? false);
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<NotificationProvider>().loadConfigs();
    });
  }

  Future<void> _openConfigModal({EmailConfig? initial}) async {
    final licenseProvider = context.read<LicenseProvider>();
    if (!_hasEmailNotificationFeature(licenseProvider)) {
      await MessageModal.showWarning(
        context,
        message: 'Este recurso exige licença com notificação por e-mail',
      );
      return;
    }

    final provider = context.read<NotificationProvider>();
    final initialConfig = initial;

    if (!mounted) {
      return;
    }

    final result = await NotificationConfigDialog.show(
      context,
      initialConfig: initialConfig,
      onTestConfiguration: (config) async {
        final success = await provider.testDraftConfiguration(config);
        if (success) {
          return null;
        }
        return provider.error ?? 'Falha ao testar configuracao SMTP';
      },
      onConnectOAuth: (config, providerType) {
        return provider.connectOAuth(
          config: config,
          provider: providerType,
        );
      },
      onReconnectOAuth: (config, providerType) {
        return provider.reconnectOAuth(
          config: config,
          provider: providerType,
        );
      },
      onDisconnectOAuth: provider.disconnectOAuth,
    );

    if (result == null || !mounted) {
      return;
    }

    final success = await provider.saveConfig(result);

    if (!mounted) return;

    if (success) {
      await MessageModal.showSuccess(
        context,
        message: 'Configuração salva com sucesso',
      );
    } else {
      await MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao salvar configuração',
      );
    }
  }

  Future<void> _createTarget() async {
    final provider = context.read<NotificationProvider>();
    final selectedConfig = provider.selectedConfig;
    if (selectedConfig == null) {
      await MessageModal.showWarning(
        context,
        message: 'Selecione uma configuração SMTP antes de adicionar destinatários',
      );
      return;
    }

    final target = await EmailTargetDialog.show(
      context,
      emailConfigId: selectedConfig.id,
      defaultNotifyOnSuccess: selectedConfig.notifyOnSuccess,
      defaultNotifyOnError: selectedConfig.notifyOnError,
      defaultNotifyOnWarning: selectedConfig.notifyOnWarning,
    );
    if (target == null || !mounted) {
      return;
    }

    final success = await provider.addTarget(target);
    if (!mounted) {
      return;
    }

    if (success) {
      await MessageModal.showSuccess(
        context,
        message: 'Destinatário adicionado com sucesso',
      );
      return;
    }

    await MessageModal.showError(
      context,
      message: provider.error ?? 'Erro ao adicionar destinatário',
    );
  }

  Future<void> _editTarget(EmailNotificationTarget target) async {
    final provider = context.read<NotificationProvider>();
    final selectedConfig = provider.selectedConfig;
    if (selectedConfig == null) {
      return;
    }

    final updated = await EmailTargetDialog.show(
      context,
      emailConfigId: selectedConfig.id,
      defaultNotifyOnSuccess: selectedConfig.notifyOnSuccess,
      defaultNotifyOnError: selectedConfig.notifyOnError,
      defaultNotifyOnWarning: selectedConfig.notifyOnWarning,
      initialTarget: target,
    );
    if (updated == null || !mounted) {
      return;
    }

    final success = await provider.updateTarget(updated);
    if (!mounted) {
      return;
    }

    if (success) {
      await MessageModal.showSuccess(
        context,
        message: 'Destinatário atualizado com sucesso',
      );
      return;
    }

    await MessageModal.showError(
      context,
      message: provider.error ?? 'Erro ao atualizar destinatário',
    );
  }

  Future<void> _deleteTarget(EmailNotificationTarget target) async {
    final confirmed = await _confirmDialog(
      title: 'Excluir destinatário',
      message:
          'Deseja realmente excluir o destinatário "${target.recipientEmail}"?',
    );
    if (!confirmed || !mounted) {
      return;
    }

    final provider = context.read<NotificationProvider>();
    final success = await provider.deleteTargetById(target.id);
    if (!mounted) {
      return;
    }

    if (success) {
      await MessageModal.showSuccess(
        context,
        message: 'Destinatário removido com sucesso',
      );
      return;
    }

    await MessageModal.showError(
      context,
      message: provider.error ?? 'Erro ao remover destinatário',
    );
  }

  Future<void> _toggleTargetEnabled(
    EmailNotificationTarget target,
    bool enabled,
  ) async {
    final provider = context.read<NotificationProvider>();
    final success = await provider.toggleTargetEnabled(target.id, enabled);
    if (success || !mounted) {
      return;
    }

    await MessageModal.showError(
      context,
      message: provider.error ?? 'Erro ao atualizar status do destinatário',
    );
  }

  Future<void> _deleteConfig(EmailConfig config) async {
    final confirmed = await _confirmDialog(
      title: 'Excluir configuração',
      message:
          'Deseja realmente excluir a configuração "${config.configName}"?',
    );

    if (!confirmed || !mounted) {
      return;
    }

    final provider = context.read<NotificationProvider>();
    final success = await provider.deleteConfigById(config.id);

    if (!mounted) return;

    if (success) {
      await MessageModal.showSuccess(
        context,
        message: 'Configuração removida com sucesso',
      );
    } else {
      await MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao remover configuração',
      );
    }
  }

  Future<void> _refresh() async {
    await context.read<NotificationProvider>().loadConfigs();
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          const CancelButton(),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Configuracoes de Notificacoes por E-mail'),
        commandBar: Consumer<LicenseProvider>(
          builder: (context, licenseProvider, _) {
            return _NotificationsCommandBar(
              hasEmailNotification: _hasEmailNotificationFeature(
                licenseProvider,
              ),
              onRefresh: _refresh,
              onCreateConfig: _openConfigModal,
            );
          },
        ),
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer<LicenseProvider>(
              builder: (context, licenseProvider, child) {
                return _LicenseRequirementInfoCard(
                  hasEmailNotification: _hasEmailNotificationFeature(
                    licenseProvider,
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Consumer2<NotificationProvider, LicenseProvider>(
              builder: (context, provider, licenseProvider, child) {
                return _NotificationsContentSection(
                  provider: provider,
                  hasEmailNotification: _hasEmailNotificationFeature(
                    licenseProvider,
                  ),
                  onRefresh: _refresh,
                  onCreateConfig: _openConfigModal,
                  onEditConfig: (config) => _openConfigModal(initial: config),
                  onDeleteConfig: _deleteConfig,
                  onCreateTarget: _createTarget,
                  onEditTarget: _editTarget,
                  onDeleteTarget: _deleteTarget,
                  onToggleTargetEnabled: _toggleTargetEnabled,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsCommandBar extends StatelessWidget {
  const _NotificationsCommandBar({
    required this.hasEmailNotification,
    required this.onRefresh,
    required this.onCreateConfig,
  });

  final bool hasEmailNotification;
  final VoidCallback onRefresh;
  final VoidCallback onCreateConfig;

  @override
  Widget build(BuildContext context) {
    return CommandBar(
      mainAxisAlignment: MainAxisAlignment.end,
      primaryItems: [
        CommandBarButton(
          icon: const Icon(FluentIcons.refresh),
          onPressed: onRefresh,
        ),
        CommandBarButton(
          icon: const Icon(FluentIcons.add),
          label: const Text('Nova configuração'),
          onPressed: hasEmailNotification ? onCreateConfig : null,
        ),
      ],
    );
  }
}

class _LicenseRequirementInfoCard extends StatelessWidget {
  const _LicenseRequirementInfoCard({
    required this.hasEmailNotification,
  });

  final bool hasEmailNotification;

  @override
  Widget build(BuildContext context) {
    if (hasEmailNotification) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        child: InfoBar(
          severity: InfoBarSeverity.warning,
          title: const Text('Recurso requer licença'),
          content: const Text(
            'As notificacoes por e-mail sao um recurso premium. '
            'É necessária uma licença válida com permissão para este recurso.',
          ),
          action: Button(
            child: const Text('Ver licenciamento'),
            onPressed: () {
              context.go(RouteNames.settings);
            },
          ),
        ),
      ),
    );
  }
}

class _NotificationsContentSection extends StatelessWidget {
  const _NotificationsContentSection({
    required this.provider,
    required this.hasEmailNotification,
    required this.onRefresh,
    required this.onCreateConfig,
    required this.onEditConfig,
    required this.onDeleteConfig,
    required this.onCreateTarget,
    required this.onEditTarget,
    required this.onDeleteTarget,
    required this.onToggleTargetEnabled,
  });

  final NotificationProvider provider;
  final bool hasEmailNotification;
  final VoidCallback onRefresh;
  final VoidCallback onCreateConfig;
  final ValueChanged<EmailConfig> onEditConfig;
  final ValueChanged<EmailConfig> onDeleteConfig;
  final VoidCallback onCreateTarget;
  final ValueChanged<EmailNotificationTarget> onEditTarget;
  final ValueChanged<EmailNotificationTarget> onDeleteTarget;
  final void Function(EmailNotificationTarget target, bool enabled)
  onToggleTargetEnabled;

  @override
  Widget build(BuildContext context) {
    if (provider.error != null && provider.configs.isEmpty) {
      return AppCard(
        child: InfoBar(
          severity: InfoBarSeverity.error,
          title: const Text('Erro ao carregar configuração'),
          content: Text(provider.error!),
          action: Button(
            onPressed: onRefresh,
            child: const Text('Tentar novamente'),
          ),
        ),
      );
    }

    return Column(
      children: [
        EmailConfigGrid(
          configs: provider.configs,
          selectedConfigId: provider.selectedConfigId,
          canManage: hasEmailNotification,
          isLoading: provider.isLoading,
          updatingConfigIds: provider.updatingConfigIds,
          onCreate: onCreateConfig,
          onEdit: onEditConfig,
          onDelete: onDeleteConfig,
          onSelect: (config) => provider.selectConfig(config.id),
          onToggleEnabled: (config, enabled) {
            provider.toggleConfigEnabled(config.id, enabled);
          },
        ),
        const SizedBox(height: 16),
        _EmailTargetsPanel(
          selectedConfig: provider.selectedConfig,
          targets: provider.targets,
          canManage: hasEmailNotification,
          onCreate: onCreateTarget,
          onEdit: onEditTarget,
          onDelete: onDeleteTarget,
          onToggleEnabled: onToggleTargetEnabled,
        ),
      ],
    );
  }
}

class _EmailTargetsPanel extends StatelessWidget {
  const _EmailTargetsPanel({
    required this.selectedConfig,
    required this.targets,
    required this.canManage,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleEnabled,
  });

  final EmailConfig? selectedConfig;
  final List<EmailNotificationTarget> targets;
  final bool canManage;
  final VoidCallback onCreate;
  final ValueChanged<EmailNotificationTarget> onEdit;
  final ValueChanged<EmailNotificationTarget> onDelete;
  final void Function(EmailNotificationTarget target, bool enabled)
  onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Destinatarios da configuracao selecionada',
            style: FluentTheme.of(context).typography.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configure quais destinatários receberão as notificações e '
            'quais tipos de evento (sucesso, erro ou aviso) cada um deve receber.',
          ),
          const SizedBox(height: 16),
          if (selectedConfig == null)
            const EmptyState(
              icon: FluentIcons.group,
              message:
                  'Selecione uma configuração SMTP para gerenciar destinatários',
            )
          else if (targets.isEmpty)
            EmptyState(
              icon: FluentIcons.group,
              message: 'Nenhum destinatário cadastrado para esta configuração',
              actionLabel: 'Novo destinatário',
              onAction: canManage ? onCreate : null,
            )
          else
            AppDataGrid<EmailNotificationTarget>(
              minWidth: 980,
              columns: [
                AppDataGridColumn<EmailNotificationTarget>(
                  label: 'Destinatario',
                  width: const FlexColumnWidth(2.2),
                  cellBuilder: (context, row) => Text(row.recipientEmail),
                ),
                AppDataGridColumn<EmailNotificationTarget>(
                  label: 'Sucesso',
                  width: const FlexColumnWidth(0.8),
                  cellAlignment: Alignment.center,
                  headerAlignment: Alignment.center,
                  cellBuilder: (context, row) => Text(
                    row.notifyOnSuccess ? 'Sim' : 'Nao',
                  ),
                ),
                AppDataGridColumn<EmailNotificationTarget>(
                  label: 'Erro',
                  width: const FlexColumnWidth(0.8),
                  cellAlignment: Alignment.center,
                  headerAlignment: Alignment.center,
                  cellBuilder: (context, row) => Text(
                    row.notifyOnError ? 'Sim' : 'Nao',
                  ),
                ),
                AppDataGridColumn<EmailNotificationTarget>(
                  label: 'Aviso',
                  width: const FlexColumnWidth(0.8),
                  cellAlignment: Alignment.center,
                  headerAlignment: Alignment.center,
                  cellBuilder: (context, row) => Text(
                    row.notifyOnWarning ? 'Sim' : 'Nao',
                  ),
                ),
                AppDataGridColumn<EmailNotificationTarget>(
                  label: 'Status',
                  cellBuilder: (context, row) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ToggleSwitch(
                        checked: row.enabled,
                        onChanged: canManage
                            ? (value) => onToggleEnabled(row, value)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(row.enabled ? 'Ativo' : 'Inativo'),
                    ],
                  ),
                ),
              ],
              actions: [
                AppDataGridAction<EmailNotificationTarget>(
                  icon: FluentIcons.edit,
                  tooltip: 'Editar',
                  onPressed: onEdit,
                  isEnabled: (_) => canManage,
                ),
                AppDataGridAction<EmailNotificationTarget>(
                  icon: FluentIcons.delete,
                  tooltip: 'Excluir',
                  onPressed: onDelete,
                  isEnabled: (_) => canManage,
                ),
              ],
              rows: targets,
            ),
          if (selectedConfig != null && targets.isNotEmpty && canManage) ...[
            const SizedBox(height: 12),
            Button(
              onPressed: onCreate,
              child: const Text('Novo destinatário'),
            ),
          ],
        ],
      ),
    );
  }
}
