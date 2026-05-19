import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppStatusChip renders label and optional icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: const ScaffoldPage(
          content: Center(
            child: AppStatusChip(
              label: 'Remote',
              icon: FluentIcons.cloud,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Remote'), findsOneWidget);
    expect(find.byIcon(FluentIcons.cloud), findsOneWidget);
  });
}
