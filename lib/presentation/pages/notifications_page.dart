import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/domain/entities/email_config.dart';
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
    final initialConfig = initial ?? provider.selectedConfig;
    String? initialRecipientEmail;
    if (initialConfig != null) {
      initialRecipientEmail = await provider.getPrimaryRecipientEmail(
        initialConfig.id,
      );
    }

    if (!mounted) {
      return;
    }

    final result = await NotificationConfigDialog.show(
      context,
      initialConfig: initialConfig,
      initialRecipientEmail: initialRecipientEmail,
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

    return AppCard(
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
  });

  final NotificationProvider provider;
  final bool hasEmailNotification;
  final VoidCallback onRefresh;
  final VoidCallback onCreateConfig;
  final ValueChanged<EmailConfig> onEditConfig;
  final ValueChanged<EmailConfig> onDeleteConfig;

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
          onCreate: onCreateConfig,
          onEdit: onEditConfig,
          onDelete: onDeleteConfig,
          onSelect: (config) => provider.selectConfig(config.id),
          onToggleEnabled: (config, enabled) {
            provider.toggleConfigEnabled(config.id, enabled);
          },
        ),
        const SizedBox(height: 16),
        EmailTestHistoryPanel(
          history: provider.testHistory,
          configs: provider.configs,
          isLoading: provider.isHistoryLoading,
          error: provider.historyError,
          selectedConfigId: provider.historyConfigIdFilter,
          period: provider.historyPeriod,
          onRefresh: provider.refreshTestHistory,
          onConfigChanged: provider.setHistoryConfigFilter,
          onPeriodChanged: provider.setHistoryPeriod,
        ),
      ],
    );
  }
}
