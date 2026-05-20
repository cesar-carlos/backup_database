import 'dart:async';

import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
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
      await FluentInfoBarFeedback.showWarning(
        context,
        message: appLocaleString(
          context,
          'Este recurso exige licença com notificação por e-mail.',
          'This feature requires a license with e-mail notification.',
        ),
      );
      return;
    }

    final provider = context.read<NotificationProvider>();
    if (!mounted) {
      return;
    }

    final result = await NotificationConfigDialog.show(
      context,
      initialConfig: initial,
      onTestConfiguration: (config) async {
        final smtpTestFailedMessage = appLocaleString(
          context,
          'Falha ao testar configuração SMTP.',
          'Failed to test SMTP configuration.',
        );
        final success = await provider.testDraftConfiguration(config);
        if (success) {
          return null;
        }
        return provider.error ?? smtpTestFailedMessage;
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
    if (!mounted) {
      return;
    }

    if (success) {
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Configuração salva com sucesso.',
          'Configuration saved successfully.',
        ),
      );
      return;
    }

    await MessageModal.showError(
      context,
      message:
          provider.error ??
          appLocaleString(
            context,
            'Erro ao salvar configuração.',
            'Error saving configuration.',
          ),
    );
  }

  Future<void> _createTarget() async {
    final provider = context.read<NotificationProvider>();
    final selectedConfig = provider.selectedConfig;
    if (selectedConfig == null) {
      await FluentInfoBarFeedback.showWarning(
        context,
        message: appLocaleString(
          context,
          'Selecione uma configuração SMTP antes de adicionar destinatários.',
          'Select an SMTP configuration before adding recipients.',
        ),
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
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Destinatário adicionado com sucesso.',
          'Recipient added successfully.',
        ),
      );
      return;
    }

    await MessageModal.showError(
      context,
      message:
          provider.error ??
          appLocaleString(
            context,
            'Erro ao adicionar destinatário.',
            'Error adding recipient.',
          ),
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
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Destinatário atualizado com sucesso.',
          'Recipient updated successfully.',
        ),
      );
      return;
    }

    await MessageModal.showError(
      context,
      message:
          provider.error ??
          appLocaleString(
            context,
            'Erro ao atualizar destinatário.',
            'Error updating recipient.',
          ),
    );
  }

  Future<void> _deleteTarget(EmailNotificationTarget target) async {
    final confirmed = await _confirmDialog(
      title: appLocaleString(
        context,
        'Excluir destinatário',
        'Delete recipient',
      ),
      message: appLocaleString(
        context,
        'Deseja realmente excluir o destinatário "${target.recipientEmail}"?',
        'Do you really want to delete recipient "${target.recipientEmail}"?',
      ),
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
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Destinatário removido com sucesso.',
          'Recipient removed successfully.',
        ),
      );
      return;
    }

    await MessageModal.showError(
      context,
      message:
          provider.error ??
          appLocaleString(
            context,
            'Erro ao remover destinatário.',
            'Error removing recipient.',
          ),
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
      message:
          provider.error ??
          appLocaleString(
            context,
            'Erro ao atualizar o status do destinatário.',
            'Error updating recipient status.',
          ),
    );
  }

  Future<void> _deleteConfig(EmailConfig config) async {
    final confirmed = await _confirmDialog(
      title: appLocaleString(
        context,
        'Excluir configuração',
        'Delete configuration',
      ),
      message: appLocaleString(
        context,
        'Deseja realmente excluir a configuração "${config.configName}"?',
        'Do you really want to delete configuration "${config.configName}"?',
      ),
    );

    if (!confirmed || !mounted) {
      return;
    }

    final provider = context.read<NotificationProvider>();
    final success = await provider.deleteConfigById(config.id);
    if (!mounted) {
      return;
    }

    if (success) {
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Configuração removida com sucesso.',
          'Configuration removed successfully.',
        ),
      );
      return;
    }

    await MessageModal.showError(
      context,
      message:
          provider.error ??
          appLocaleString(
            context,
            'Erro ao remover configuração.',
            'Error removing configuration.',
          ),
    );
  }

  Future<void> _toggleConfigEnabled(EmailConfig config, bool enabled) async {
    final provider = context.read<NotificationProvider>();
    final success = await provider.toggleConfigEnabled(config.id, enabled);
    if (success || !mounted) {
      return;
    }

    await MessageModal.showError(
      context,
      message:
          provider.error ??
          appLocaleString(
            context,
            'Erro ao atualizar o status da configuração.',
            'Error updating configuration status.',
          ),
    );
  }

  Future<void> _testSelectedConfig() async {
    final provider = context.read<NotificationProvider>();
    final selectedConfig = provider.selectedConfig;
    if (selectedConfig == null) {
      await FluentInfoBarFeedback.showWarning(
        context,
        message: appLocaleString(
          context,
          'Selecione uma configuração antes de testar o SMTP.',
          'Select a configuration before testing SMTP.',
        ),
      );
      return;
    }

    final success = await provider.testConfiguration(selectedConfig.id);
    if (!mounted) {
      return;
    }

    if (success) {
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Teste SMTP concluído com sucesso.',
          'SMTP test completed successfully.',
        ),
      );
      return;
    }

    await MessageModal.showError(
      context,
      message:
          provider.error ??
          appLocaleString(
            context,
            'Falha ao testar a configuração SMTP.',
            'Failed to test the SMTP configuration.',
          ),
    );
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
      builder: (dialogContext) => ContentDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          const CancelButton(),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(appLocaleString(context, 'Confirmar', 'Confirm')),
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
        title: Text(
          appLocaleString(
            context,
            'Configurações de notificações por e-mail',
            'E-mail notification settings',
          ),
        ),
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
                  onCreateConfig: _openConfigModal,
                  onEditConfig: (config) => _openConfigModal(initial: config),
                  onDeleteConfig: _deleteConfig,
                  onCreateTarget: _createTarget,
                  onEditTarget: _editTarget,
                  onDeleteTarget: _deleteTarget,
                  onToggleConfigEnabled: _toggleConfigEnabled,
                  onToggleTargetEnabled: _toggleTargetEnabled,
                  onTestSelectedConfig: _testSelectedConfig,
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
          label: Text(
            appLocaleString(
              context,
              'Nova configuração',
              'New configuration',
            ),
          ),
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
          title: Text(
            appLocaleString(
              context,
              'Recurso requer licença',
              'License required',
            ),
          ),
          content: Text(
            appLocaleString(
              context,
              'As notificações por e-mail são um recurso premium. É necessária uma licença válida com permissão para este recurso.',
              'E-mail notifications are a premium feature. A valid license with permission for this feature is required.',
            ),
          ),
          action: Button(
            child: Text(
              appLocaleString(context, 'Ver licenciamento', 'View licensing'),
            ),
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
    required this.onCreateConfig,
    required this.onEditConfig,
    required this.onDeleteConfig,
    required this.onCreateTarget,
    required this.onEditTarget,
    required this.onDeleteTarget,
    required this.onToggleConfigEnabled,
    required this.onToggleTargetEnabled,
    required this.onTestSelectedConfig,
  });

  final NotificationProvider provider;
  final bool hasEmailNotification;
  final VoidCallback onCreateConfig;
  final ValueChanged<EmailConfig> onEditConfig;
  final ValueChanged<EmailConfig> onDeleteConfig;
  final VoidCallback onCreateTarget;
  final ValueChanged<EmailNotificationTarget> onEditTarget;
  final ValueChanged<EmailNotificationTarget> onDeleteTarget;
  final void Function(EmailConfig config, bool enabled) onToggleConfigEnabled;
  final void Function(EmailNotificationTarget target, bool enabled)
  onToggleTargetEnabled;
  final VoidCallback onTestSelectedConfig;

  @override
  Widget build(BuildContext context) {
    if (provider.error != null && provider.configs.isEmpty) {
      return AppCard(
        child: InfoBar(
          severity: InfoBarSeverity.error,
          title: Text(
            appLocaleString(
              context,
              'Erro ao carregar configurações',
              'Error loading configurations',
            ),
          ),
          content: Text(provider.error!),
          action: Button(
            onPressed: provider.loadConfigs,
            child: Text(
              appLocaleString(context, 'Tentar novamente', 'Try again'),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = <Widget>[
          EmailConfigList(
            configs: provider.configs,
            selectedConfigId: provider.selectedConfigId,
            canManage: hasEmailNotification,
            isLoading: provider.isLoading,
            updatingConfigIds: provider.updatingConfigIds,
            onCreate: onCreateConfig,
            onEdit: onEditConfig,
            onDelete: onDeleteConfig,
            onSelect: (config) => unawaited(provider.selectConfig(config.id)),
            onToggleEnabled: onToggleConfigEnabled,
          ),
          NotificationDetailPanel(
            selectedConfig: provider.selectedConfig,
            configs: provider.configs,
            targets: provider.targets,
            testHistory: provider.testHistory,
            historyError: provider.historyError,
            isHistoryLoading: provider.isHistoryLoading,
            historyPeriod: provider.historyPeriod,
            historyConfigIdFilter: provider.historyConfigIdFilter,
            canManage: hasEmailNotification,
            isTestingSelectedConfig:
                provider.selectedConfig != null &&
                provider.isConfigUnderTest(provider.selectedConfig!.id),
            onEditConfig: onEditConfig,
            onDeleteConfig: onDeleteConfig,
            onAddTarget: onCreateTarget,
            onEditTarget: onEditTarget,
            onDeleteTarget: onDeleteTarget,
            onToggleConfigEnabled: onToggleConfigEnabled,
            onToggleTargetEnabled: onToggleTargetEnabled,
            onTestConfig: onTestSelectedConfig,
            onHistoryConfigChanged: (value) {
              unawaited(provider.setHistoryConfigFilter(value));
            },
            onHistoryPeriodChanged: (value) {
              unawaited(provider.setHistoryPeriod(value));
            },
            onRefreshHistory: provider.refreshTestHistory,
          ),
        ];

        if (constraints.maxWidth >= 1120) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 360, child: content[0]),
              const SizedBox(width: 16),
              Expanded(child: content[1]),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            content[0],
            const SizedBox(height: 16),
            content[1],
          ],
        );
      },
    );
  }
}
