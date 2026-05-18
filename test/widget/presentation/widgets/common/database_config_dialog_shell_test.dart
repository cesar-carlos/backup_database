import 'dart:async';

import 'package:backup_database/presentation/widgets/organisms/database_config_dialog_shell.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Escape pops route when onDismiss is null', (
    WidgetTester tester,
  ) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      FluentApp(
        navigatorKey: navKey,
        home: ScaffoldPage(
          content: Button(
            child: const Text('Push'),
            onPressed: () {
              unawaited(
                navKey.currentState!.push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const DatabaseConfigDialogShell(
                      constraints: BoxConstraints(maxWidth: 400),
                      title: Text('T'),
                      body: Text('Body'),
                      dialogActions: [],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(navKey.currentState!.canPop(), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(navKey.currentState!.canPop(), isFalse);
  });

  testWidgets('Escape invokes onDismiss', (WidgetTester tester) async {
    final navKey = GlobalKey<NavigatorState>();
    var dismissCalls = 0;
    await tester.pumpWidget(
      FluentApp(
        navigatorKey: navKey,
        home: ScaffoldPage(
          content: Button(
            child: const Text('Push'),
            onPressed: () {
              unawaited(
                navKey.currentState!.push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext dialogContext) =>
                        DatabaseConfigDialogShell(
                          constraints: const BoxConstraints(maxWidth: 400),
                          title: const Text('T'),
                          body: const Text('Body'),
                          dialogActions: const [],
                          onDismiss: () {
                            dismissCalls++;
                            Navigator.of(dialogContext).pop<void>();
                          },
                        ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(dismissCalls, 1);
    expect(navKey.currentState!.canPop(), isFalse);
  });

  testWidgets('Ctrl+Enter invokes onSubmitIntent when focused', (
    WidgetTester tester,
  ) async {
    var submitCalls = 0;
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: DatabaseConfigDialogShell(
            constraints: const BoxConstraints(maxWidth: 400),
            title: const Text('T'),
            body: const Text('Body'),
            dialogActions: const [],
            onSubmitIntent: () {
              submitCalls++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(submitCalls, 1);
  });
}
