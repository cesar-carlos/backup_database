import 'dart:async';

import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/presentation/widgets/organisms/message_modal.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MessageModal.show dismisses with Escape', (
    WidgetTester tester,
  ) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        darkTheme: AppTheme.darkFluentTheme,
        themeMode: ThemeMode.light,
        locale: const Locale('en', 'US'),
        home: Builder(
          builder: (BuildContext context) {
            hostContext = context;
            return ScaffoldPage(
              content: Button(
                onPressed: () {
                  unawaited(
                    MessageModal.show(
                      hostContext,
                      title: 'Modal title',
                      message: 'Modal body text',
                    ),
                  );
                },
                child: const Text('open-message-modal'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-message-modal'));
    await tester.pumpAndSettle();
    expect(find.text('Modal body text'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Modal body text'), findsNothing);
  });

  testWidgets('MessageModal.showConfirm dismisses with Escape', (
    WidgetTester tester,
  ) async {
    late BuildContext hostContext;
    bool? confirmResult;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        darkTheme: AppTheme.darkFluentTheme,
        themeMode: ThemeMode.light,
        locale: const Locale('en', 'US'),
        home: Builder(
          builder: (BuildContext context) {
            hostContext = context;
            return ScaffoldPage(
              content: Button(
                onPressed: () async {
                  confirmResult = await MessageModal.showConfirm(
                    hostContext,
                    title: 'Confirm title',
                    message: 'Confirm body',
                    confirmLabel: 'Proceed',
                  );
                },
                child: const Text('open-confirm'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm body'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Confirm body'), findsNothing);
    expect(confirmResult, isFalse);
  });
}
