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
  return licenseProvider.hasValidLicense &&
      licenseProvider.currentLicense != null &&
      licenseProvider.currentLicense!.hasFeature(
        LicenseFeatures.emailNotification,
      );
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
        message: 'Este recurso exige licenca com notificacao por e-mail',
      );
      return;
    }

    final provider = context.read<NotificationProvider>();
    final result = await NotificationConfigDialog.show(
      context,
      initialConfig: initial ?? provider.selectedConfig,
    );

    if (result == null || !mounted) {
      return;
    }

    final success = await provider.saveConfig(result);

    if (!mounted) return;

    if (success) {
      await MessageModal.showSuccess(
        context,
        message: 'Configuracao salva com sucesso',
      );
    } else {
      await MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao salvar configuracao',
      );
    }
  }

  Future<void> _deleteConfig(EmailConfig config) async {
    final confirmed = await _confirmDialog(
      title: 'Excluir configuracao',
      message:
          'Deseja realmente excluir a configuracao "${config.configName}"?',
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
        message: 'Configuracao removida com sucesso',
      );
    } else {
      await MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao remover configuracao',
      );
    }
  }

  Future<void> _openTargetModal({EmailNotificationTarget? initial}) async {
    final provider = context.read<NotificationProvider>();
    final selected = provider.selectedConfig;
    if (selected == null) {
      await MessageModal.showWarning(
        context,
        message: 'Selecione uma configuracao SMTP para continuar',
      );
      return;
    }

    final result = await EmailTargetDialog.show(
      context,
      emailConfigId: selected.id,
      initialTarget: initial,
    );

    if (result == null || !mounted) {
      return;
    }

    final success = initial == null
        ? await provider.addTarget(result)
        : await provider.updateTarget(result);

    if (!mounted) return;

    if (success) {
      await MessageModal.showSuccess(
        context,
        message: initial == null
            ? 'Destinatario adicionado com sucesso'
            : 'Destinatario atualizado com sucesso',
      );
    } else {
      await MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao salvar destinatario',
      );
    }
  }

  Future<void> _deleteTarget(EmailNotificationTarget target) async {
    final confirmed = await _confirmDialog(
      title: 'Excluir destinatario',
      message: 'Deseja excluir o destinatario "${target.recipientEmail}"?',
    );

    if (!confirmed || !mounted) {
      return;
    }

    final provider = context.read<NotificationProvider>();
    final success = await provider.deleteTargetById(target.id);

    if (!mounted) return;

    if (!success) {
      await MessageModal.showError(
        context,
        message: provider.error ?? 'Erro ao excluir destinatario',
      );
    }
  }

  Future<void> _testConnection() async {
    final licenseProvider = context.read<LicenseProvider>();
    if (!_hasEmailNotificationFeature(licenseProvider)) {
      return;
    }

    final provider = context.read<NotificationProvider>();
    final success = await provider.testConfiguration();
    if (!mounted) return;

    if (success) {
      await MessageModal.showSuccess(
        context,
        message: 'Teste de conexao realizado com sucesso',
      );
      return;
    }

    await MessageModal.showError(
      context,
      message: provider.error ?? 'Erro ao testar conexao',
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
        commandBar: Consumer2<NotificationProvider, LicenseProvider>(
          builder: (context, provider, licenseProvider, _) {
            return _NotificationsCommandBar(
              hasEmailNotification: _hasEmailNotificationFeature(
                licenseProvider,
              ),
              selectedConfig: provider.selectedConfig,
              onRefresh: _refresh,
              onCreateConfig: _openConfigModal,
              onEditConfig: (config) => _openConfigModal(initial: config),
              onDeleteConfig: _deleteConfig,
            );
          },
        ),
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
            const SizedBox(height: 16),
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
                  onTestConnection: _testConnection,
                  onAddTarget: _openTargetModal,
                  onEditTarget: (target) => _openTargetModal(initial: target),
                  onDeleteTarget: _deleteTarget,
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
    required this.selectedConfig,
    required this.onRefresh,
    required this.onCreateConfig,
    required this.onEditConfig,
    required this.onDeleteConfig,
  });

  final bool hasEmailNotification;
  final EmailConfig? selectedConfig;
  final VoidCallback onRefresh;
  final VoidCallback onCreateConfig;
  final ValueChanged<EmailConfig> onEditConfig;
  final ValueChanged<EmailConfig> onDeleteConfig;

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
          label: const Text('Nova configuracao'),
          onPressed: hasEmailNotification ? onCreateConfig : null,
        ),
        CommandBarButton(
          icon: const Icon(FluentIcons.edit),
          label: const Text('Editar'),
          onPressed: hasEmailNotification && selectedConfig != null
              ? () => onEditConfig(selectedConfig!)
              : null,
        ),
        CommandBarButton(
          icon: const Icon(FluentIcons.delete),
          label: const Text('Excluir'),
          onPressed: hasEmailNotification && selectedConfig != null
              ? () => onDeleteConfig(selectedConfig!)
              : null,
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

    return AppCard(
      child: InfoBar(
        severity: InfoBarSeverity.warning,
        title: const Text('Recurso requer licenca'),
        content: const Text(
          'As notificacoes por e-mail sao um recurso premium. '
          'E necessaria uma licenca valida com permissao para este recurso.',
        ),
        action: Button(
          child: const Text('Ver licenciamento'),
          onPressed: () {
            context.go(RouteNames.settings);
          },
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
    required this.onTestConnection,
    required this.onAddTarget,
    required this.onEditTarget,
    required this.onDeleteTarget,
  });

  final NotificationProvider provider;
  final bool hasEmailNotification;
  final VoidCallback onRefresh;
  final VoidCallback onCreateConfig;
  final ValueChanged<EmailConfig> onEditConfig;
  final ValueChanged<EmailConfig> onDeleteConfig;
  final Future<void> Function() onTestConnection;
  final Future<void> Function() onAddTarget;
  final ValueChanged<EmailNotificationTarget> onEditTarget;
  final ValueChanged<EmailNotificationTarget> onDeleteTarget;

  @override
  Widget build(BuildContext context) {
    if (provider.error != null && provider.configs.isEmpty) {
      return AppCard(
        child: InfoBar(
          severity: InfoBarSeverity.error,
          title: const Text('Erro ao carregar configuracao'),
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
          isTesting: provider.isTesting,
          onCreate: onCreateConfig,
          onEdit: onEditConfig,
          onDelete: onDeleteConfig,
          onSelect: (config) => provider.selectConfig(config.id),
          onTest: onTestConnection,
          onToggleEnabled: (config, enabled) {
            provider.toggleConfigEnabled(config.id, enabled);
          },
        ),
        const SizedBox(height: 16),
        EmailTargetGrid(
          targets: provider.targets,
          canManage: hasEmailNotification,
          hasSelectedConfig: provider.selectedConfig != null,
          onAdd: onAddTarget,
          onEdit: onEditTarget,
          onDelete: onDeleteTarget,
          onToggleEnabled: (target, enabled) {
            provider.toggleTargetEnabled(target.id, enabled);
          },
        ),
      ],
    );
  }
}
