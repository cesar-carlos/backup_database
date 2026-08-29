import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/presentation/widgets/atoms/app_icon_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppIconButton exposes tooltip and invokes onPressed', (
    WidgetTester tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: ScaffoldPage(
          content: AppIconButton(
            label: 'Edit',
            icon: FluentIcons.edit,
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byIcon(FluentIcons.edit), findsOneWidget);

    await tester.tap(find.byType(AppIconButton));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });
}
