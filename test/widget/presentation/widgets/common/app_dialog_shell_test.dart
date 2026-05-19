import 'package:backup_database/presentation/widgets/molecules/cancel_button.dart';
import 'package:backup_database/presentation/widgets/organisms/app_dialog_shell.dart';
import 'package:fluent_ui/fluent_ui.dart';
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
}
