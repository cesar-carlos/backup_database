import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/presentation/widgets/atoms/app_callout.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppCallout renders message and default info icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: const ScaffoldPage(
          content: AppCallout(message: 'Fill host and port'),
        ),
      ),
    );

    expect(find.text('Fill host and port'), findsOneWidget);
    expect(find.byIcon(FluentIcons.info), findsOneWidget);
  });

  testWidgets('AppCallout warning tone uses warning icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: const ScaffoldPage(
          content: AppCallout(
            message: 'Be careful',
            tone: AppCalloutTone.warning,
          ),
        ),
      ),
    );

    expect(find.byIcon(FluentIcons.warning), findsOneWidget);
  });
}
