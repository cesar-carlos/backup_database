import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/presentation/widgets/backup/backup_progress_dialog.dart';
import 'package:backup_database/presentation/widgets/backup/global_backup_progress_listener.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late BackupProgressProvider progress;
  late GlobalKey<NavigatorState> navigator;

  setUp(() {
    progress = BackupProgressProvider();
    navigator = GlobalKey<NavigatorState>();
  });
  tearDown(() => progress.dispose());

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: progress,
        child: FluentApp(
          navigatorKey: navigator,
          locale: const Locale('en'),
          home: const GlobalBackupProgressListener(
            child: ScaffoldPage(content: Text('Home')),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('back and barrier cannot erase a running backup', (tester) async {
    await mount(tester);
    progress.startBackup('A');
    await animate(tester);
    await navigator.currentState!.maybePop();
    await tester.tapAt(const Offset(5, 5));
    await animate(tester);
    expect(progress.isRunning, isTrue);
    expect(find.byType(BackupProgressDialog), findsOneWidget);
    expect(find.textContaining('Elapsed time:'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('next backup reuses the still open result dialog', (
    tester,
  ) async {
    await mount(tester);
    progress.startBackup('A');
    await animate(tester);
    progress.completeBackup();
    await animate(tester);
    progress.startBackup('B');
    await animate(tester);
    expect(
      find.byType(BackupProgressDialog, skipOffstage: false),
      findsOneWidget,
    );
    expect(progress.currentBackupName, 'B');
    progress.completeBackup();
    await animate(tester);
    await tester.tap(find.text('Close'));
    await animate(tester);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(BackupProgressDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('route removal does not release execution state', (tester) async {
    await mount(tester);
    progress.startBackup('A');
    await animate(tester);
    navigator.currentState!.pop();
    await animate(tester);
    expect(progress.isRunning, isTrue);
    expect(progress.tryStartBackup('B'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirmation for a previous backup cannot cancel the next', (
    tester,
  ) async {
    await mount(tester);
    progress.startBackup('A');
    progress.setCurrentHistoryId('a');
    await animate(tester);
    await tester.tap(find.text('Cancel'));
    await animate(tester);
    progress.completeBackup();
    progress.startBackup('B');
    progress.setCurrentHistoryId('b');
    await tester.tap(find.text('Cancel now'));
    await animate(tester);
    expect(progress.currentBackupName, 'B');
    expect(progress.currentProgress!.cancelRequested, isFalse);
    expect(find.text('Cancelamento não confirmado'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
