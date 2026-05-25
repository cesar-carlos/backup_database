import 'package:backup_database/application/providers/notification_provider.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/presentation/widgets/notifications/email_config_list.dart';
import 'package:backup_database/presentation/widgets/notifications/notification_detail_panel.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return FluentApp(
      locale: const Locale('en', 'US'),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(1440, 2400)),
        child: SingleChildScrollView(child: child),
      ),
    );
  }

  final configA = EmailConfig(
    id: 'config-a',
    configName: 'SMTP Alpha',
    smtpServer: 'smtp-alpha.example.com',
    username: 'alpha@example.com',
    password: 'secret',
    recipients: const ['dest-a@example.com'],
  );
  final configB = EmailConfig(
    id: 'config-b',
    configName: 'SMTP Beta',
    smtpServer: 'smtp-beta.example.com',
    username: 'beta@example.com',
    password: 'secret',
    recipients: const ['dest-b@example.com'],
  );
  final targetA = EmailNotificationTarget(
    id: 'target-a',
    emailConfigId: 'config-a',
    recipientEmail: 'alpha-recipient@example.com',
  );
  final historyA = EmailTestAudit(
    id: 'history-a',
    configId: 'config-a',
    correlationId: 'corr-a',
    recipientEmail: targetA.recipientEmail,
    senderEmail: configA.username,
    smtpServer: configA.smtpServer,
    smtpPort: configA.smtpPort,
    status: 'success',
  );

  testWidgets('EmailConfigList renders configurations and selection callback', (
    tester,
  ) async {
    EmailConfig? selected;

    await tester.pumpWidget(
      wrap(
        EmailConfigList(
          configs: [configA, configB],
          selectedConfigId: configA.id,
          canManage: true,
          isLoading: false,
          updatingConfigIds: const {},
          onCreate: () {},
          onEdit: (_) {},
          onDelete: (_) {},
          onSelect: (config) => selected = config,
          onToggleEnabled: (_, value) {},
        ),
      ),
    );

    expect(find.text('SMTP configurations'), findsOneWidget);
    expect(find.text('SMTP Alpha'), findsOneWidget);
    expect(find.text('SMTP Beta'), findsOneWidget);

    await tester.tap(find.text('SMTP Beta'));
    await tester.pump();

    expect(selected?.id, configB.id);
  });

  testWidgets('EmailConfigList shows empty state when there are no configs', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        EmailConfigList(
          configs: const [],
          selectedConfigId: null,
          canManage: true,
          isLoading: false,
          updatingConfigIds: const {},
          onCreate: () {},
          onEdit: (_) {},
          onDelete: (_) {},
          onSelect: (_) {},
          onToggleEnabled: (_, value) {},
        ),
      ),
    );

    expect(find.text('No e-mail configuration registered'), findsOneWidget);
  });

  testWidgets(
    'NotificationDetailPanel shows summary, recipients, and SMTP history',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          NotificationDetailPanel(
            selectedConfig: configA,
            configs: [configA, configB],
            targets: [targetA],
            testHistory: [historyA],
            historyError: null,
            isHistoryLoading: false,
            historyPeriod: NotificationHistoryPeriod.last7Days,
            historyConfigIdFilter: configA.id,
            canManage: true,
            isTestingSelectedConfig: false,
            onEditConfig: (_) {},
            onDeleteConfig: (_) {},
            onAddTarget: () {},
            onEditTarget: (_) {},
            onDeleteTarget: (_) {},
            onToggleConfigEnabled: (_, enabled) {},
            onToggleTargetEnabled: (_, enabled) {},
            onTestConfig: () {},
            onHistoryConfigChanged: (_) {},
            onHistoryPeriodChanged: (_) {},
            onRefreshHistory: () {},
          ),
        ),
      );

      expect(find.text('Configuration summary'), findsOneWidget);
      expect(find.text('Recipients'), findsOneWidget);
      expect(find.text('SMTP test history'), findsOneWidget);
      expect(find.text('alpha-recipient@example.com'), findsWidgets);
      expect(find.text('smtp-alpha.example.com'), findsWidgets);
    },
  );

  testWidgets(
    'NotificationDetailPanel shows recipient empty state when config has no targets',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          NotificationDetailPanel(
            selectedConfig: configA,
            configs: [configA],
            targets: const [],
            testHistory: const [],
            historyError: null,
            isHistoryLoading: false,
            historyPeriod: NotificationHistoryPeriod.last7Days,
            historyConfigIdFilter: configA.id,
            canManage: true,
            isTestingSelectedConfig: false,
            onEditConfig: (_) {},
            onDeleteConfig: (_) {},
            onAddTarget: () {},
            onEditTarget: (_) {},
            onDeleteTarget: (_) {},
            onToggleConfigEnabled: (_, enabled) {},
            onToggleTargetEnabled: (_, enabled) {},
            onTestConfig: () {},
            onHistoryConfigChanged: (_) {},
            onHistoryPeriodChanged: (_) {},
            onRefreshHistory: () {},
          ),
        ),
      );

      expect(
        find.text('No recipients registered for SMTP Alpha.'),
        findsOneWidget,
      );
    },
  );
}
