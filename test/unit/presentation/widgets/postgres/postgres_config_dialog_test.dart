import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/presentation/widgets/postgres/postgres_config_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPostgresBackupService extends Mock
    implements IPostgresBackupService {}

void main() {
  late _MockPostgresBackupService mockPostgres;

  setUp(() async {
    mockPostgres = _MockPostgresBackupService();
    if (getIt.isRegistered<IPostgresBackupService>()) {
      await getIt.unregister<IPostgresBackupService>();
    }
    getIt.registerSingleton<IPostgresBackupService>(mockPostgres);
  });

  tearDown(() async {
    if (getIt.isRegistered<IPostgresBackupService>()) {
      await getIt.unregister<IPostgresBackupService>();
    }
  });

  testWidgets('shows PostgreSQL new configuration title (en)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('en'),
        home: PostgresConfigDialog(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New PostgreSQL configuration'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
  });
}
