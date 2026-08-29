import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/presentation/widgets/molecules/labeled_toggle.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LabeledToggle shows title and toggles value', (
    WidgetTester tester,
  ) async {
    var enabled = false;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: ScaffoldPage(
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return LabeledToggle(
                title: 'Enabled',
                description: 'Use in schedules',
                value: enabled,
                onChanged: (bool value) {
                  setState(() => enabled = value);
                },
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Enabled'), findsOneWidget);
    expect(find.text('Use in schedules'), findsOneWidget);

    await tester.tap(find.byType(ToggleSwitch));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
  });
}
