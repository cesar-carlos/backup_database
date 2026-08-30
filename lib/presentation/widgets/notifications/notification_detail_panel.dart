import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/notifications/email_test_history_panel.dart';
import 'package:backup_database/presentation/widgets/notifications/notification_detail_panel/notification_recipients_section.dart';
import 'package:backup_database/presentation/widgets/notifications/notification_detail_panel/notification_summary_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

class NotificationDetailPanel extends StatelessWidget {
  const NotificationDetailPanel({
    required this.selectedConfig,
    required this.configs,
    required this.targets,
    required this.testHistory,
    required this.historyError,
    required this.isHistoryLoading,
    required this.historyPeriod,
    required this.historyConfigIdFilter,
    required this.canManage,
    required this.isTestingSelectedConfig,
    required this.onEditConfig,
    required this.onDeleteConfig,
    required this.onAddTarget,
    required this.onEditTarget,
    required this.onDeleteTarget,
    required this.onToggleConfigEnabled,
    required this.onToggleTargetEnabled,
    required this.onTestConfig,
    required this.onHistoryConfigChanged,
    required this.onHistoryPeriodChanged,
    required this.onRefreshHistory,
    super.key,
  });

  final EmailConfig? selectedConfig;
  final List<EmailConfig> configs;
  final List<EmailNotificationTarget> targets;
  final List<EmailTestAudit> testHistory;
  final String? historyError;
  final bool isHistoryLoading;
  final NotificationHistoryPeriod historyPeriod;
  final String? historyConfigIdFilter;
  final bool canManage;
  final bool isTestingSelectedConfig;
  final ValueChanged<EmailConfig> onEditConfig;
  final ValueChanged<EmailConfig> onDeleteConfig;
  final VoidCallback onAddTarget;
  final ValueChanged<EmailNotificationTarget> onEditTarget;
  final ValueChanged<EmailNotificationTarget> onDeleteTarget;
  final void Function(EmailConfig config, bool enabled) onToggleConfigEnabled;
  final void Function(EmailNotificationTarget target, bool enabled)
  onToggleTargetEnabled;
  final VoidCallback onTestConfig;
  final ValueChanged<String?> onHistoryConfigChanged;
  final ValueChanged<NotificationHistoryPeriod> onHistoryPeriodChanged;
  final VoidCallback onRefreshHistory;

  @override
  Widget build(BuildContext context) {
    final config = selectedConfig;
    if (config == null) {
      return AppCard(
        child: EmptyState(
          icon: FluentIcons.mail,
          message: appLocaleString(
            context,
            'Selecione uma configuração SMTP para visualizar os detalhes.',
            'Select an SMTP configuration to view details.',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NotificationSummaryCard(
          config: config,
          targets: targets,
          testHistory: testHistory,
          canManage: canManage,
          isTesting: isTestingSelectedConfig,
          onEdit: () => onEditConfig(config),
          onDelete: () => onDeleteConfig(config),
          onToggleEnabled: (value) => onToggleConfigEnabled(config, value),
          onTest: onTestConfig,
        ),
        const SizedBox(height: 16),
        NotificationRecipientsSection(
          config: config,
          targets: targets,
          canManage: canManage,
          onAddTarget: onAddTarget,
          onEditTarget: onEditTarget,
          onDeleteTarget: onDeleteTarget,
          onToggleTargetEnabled: onToggleTargetEnabled,
        ),
        const SizedBox(height: 16),
        EmailTestHistoryPanel(
          history: testHistory,
          configs: configs,
          isLoading: isHistoryLoading,
          error: historyError,
          selectedConfigId: historyConfigIdFilter,
          period: historyPeriod,
          onConfigChanged: onHistoryConfigChanged,
          onPeriodChanged: onHistoryPeriodChanged,
          onRefresh: onRefreshHistory,
        ),
      ],
    );
  }
}
