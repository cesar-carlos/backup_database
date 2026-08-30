import 'package:backup_database/presentation/widgets/molecules/cancel_button.dart';
import 'package:backup_database/presentation/widgets/organisms/app_dialog_shell.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppDialogShell renders title, content and actions', (
    WidgetTester tester,
  ) async {
    var submitted = false;

    await tester.pumpWidget(
      FluentApp(
        home: AppDialogShell(
          title: const Text('Dialog title'),
          content: const Text('Dialog body'),
          onSubmitIntent: () {
            submitted = true;
          },
          actions: [
            CancelButton(onPressed: () {}),
            FilledButton(
              onPressed: () {},
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Dialog title'), findsOneWidget);
    expect(find.text('Dialog body'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(submitted, isTrue);
  });

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
              navKey.currentState!.push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const AppDialogShell(
                    constraints: BoxConstraints(maxWidth: 400),
                    title: Text('T'),
                    content: Text('Body'),
                    actions: [],
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
              navKey.currentState!.push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext dialogContext) => AppDialogShell(
                    constraints: const BoxConstraints(maxWidth: 400),
                    title: const Text('T'),
                    content: const Text('Body'),
                    actions: const [],
                    onDismiss: () {
                      dismissCalls++;
                      Navigator.of(dialogContext).pop<void>();
                    },
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
}
