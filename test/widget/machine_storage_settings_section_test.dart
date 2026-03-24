import 'package:backup_database/presentation/widgets/settings/machine_storage_settings_section.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MachineStorageSettingsSection renders storage actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: MachineStorageSettingsSection(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(MachineStorageSettingsSection), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
  });
}
