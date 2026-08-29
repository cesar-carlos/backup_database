import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/molecules/schedule_dependency_list.dart';
import 'package:backup_database/presentation/widgets/organisms/schedule_blocked_deletion_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ScheduleBlockedDeletionDialog lists schedules and actions', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final schedule = Schedule(
      name: 'Nightly SQL',
      databaseConfigId: 'cfg-1',
      databaseType: DatabaseType.sqlServer,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      destinationIds: const <String>[],
      backupFolder: 'bf',
    );

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        theme: AppTheme.lightFluentTheme,
        home: ScaffoldPage(
          content: ScheduleBlockedDeletionDialog(
            bodyParagraphs: const <String>[
              'Cannot delete this item.',
              'Remove the schedules first.',
            ],
            schedules: [schedule],
          ),
        ),
      ),
    );

    expect(find.text('Deletion blocked by dependencies'), findsOneWidget);
    expect(find.text('Cannot delete this item.'), findsOneWidget);
    expect(find.text('Remove the schedules first.'), findsOneWidget);
    expect(find.byType(ScheduleDependencyList), findsOneWidget);
    expect(find.text('Nightly SQL'), findsOneWidget);
    expect(find.text('Go to Schedules'), findsOneWidget);
  });
}
