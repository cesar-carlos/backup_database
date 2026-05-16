import 'package:backup_database/presentation/widgets/common/password_field.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toggle switches TextBox obscureText', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: ScaffoldPage(
          content: PasswordField(
            controller: TextEditingController(),
          ),
        ),
      ),
    );

    final textBoxFinder = find.byType(TextBox);
    expect(tester.widget<TextBox>(textBoxFinder).obscureText, isTrue);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(tester.widget<TextBox>(textBoxFinder).obscureText, isFalse);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(tester.widget<TextBox>(textBoxFinder).obscureText, isTrue);
  });

  testWidgets('when enabled is false toggle has no onPressed', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('en'),
        home: ScaffoldPage(
          content: PasswordField(enabled: false),
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });
}
