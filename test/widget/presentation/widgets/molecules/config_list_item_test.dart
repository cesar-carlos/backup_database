import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/presentation/widgets/atoms/app_icon_button.dart';
import 'package:backup_database/presentation/widgets/molecules/config_list_item.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ConfigListItem shows duplicate action when provided', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var duplicated = false;
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        theme: AppTheme.lightFluentTheme,
        home: ScaffoldPage(
          content: ConfigListItem(
            name: 'Prod',
            subtitle: const Text('localhost'),
            icon: FluentIcons.database,
            enabled: true,
            onDuplicate: () => duplicated = true,
          ),
        ),
      ),
    );

    expect(find.byType(AppIconButton), findsOneWidget);
    await tester.tap(find.byType(AppIconButton));
    await tester.pumpAndSettle();
    expect(duplicated, isTrue);
  });
}
