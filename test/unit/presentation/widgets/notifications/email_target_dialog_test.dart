import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/presentation/widgets/notifications/email_target_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _findTextPtOrEn(String pt, String en) {
  return find.byWidgetPredicate((widget) {
    if (widget is Text) {
      return widget.data == pt || widget.data == en;
    }
    if (widget is SelectableText) {
      return widget.data == pt || widget.data == en;
    }
    return false;
  });
}

void main() {
  Widget buildDialog({EmailNotificationTarget? initialTarget}) {
    return FluentApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(1280, 900)),
        child: EmailTargetDialog(
          emailConfigId: 'config-a',
          defaultNotifyOnSuccess: true,
          defaultNotifyOnError: true,
          defaultNotifyOnWarning: false,
          initialTarget: initialTarget,
        ),
      ),
    );
  }

  testWidgets('renders new recipient sections and event toggles', (tester) async {
    await tester.pumpWidget(buildDialog());
    await tester.pumpAndSettle();

    expect(_findTextPtOrEn('Identification', 'Identification'), findsOneWidget);
    expect(_findTextPtOrEn('Events', 'Events'), findsOneWidget);
    expect(_findTextPtOrEn('Status', 'Status'), findsOneWidget);
    expect(_findTextPtOrEn('Notify on success', 'Notify on success'), findsOneWidget);
    expect(_findTextPtOrEn('Recipient active', 'Recipient active'), findsOneWidget);
  });

  testWidgets('renders edit recipient title when editing', (tester) async {
    final target = EmailNotificationTarget(
      id: 'target-a',
      emailConfigId: 'config-a',
      recipientEmail: 'ops@example.com',
    );

    await tester.pumpWidget(buildDialog(initialTarget: target));
    await tester.pumpAndSettle();

    expect(_findTextPtOrEn('Edit recipient', 'Edit recipient'), findsOneWidget);
    expect(find.text('ops@example.com'), findsOneWidget);
  });
}
