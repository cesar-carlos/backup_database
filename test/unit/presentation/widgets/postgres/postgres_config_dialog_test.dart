import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/presentation/widgets/postgres/postgres_config_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockPostgresBackupService extends Mock
    implements IPostgresBackupService {}

class _MockPostgresConfigProvider extends Mock
    implements PostgresConfigProvider {}

void main() {
  late _MockPostgresBackupService mockPostgres;
  late _MockPostgresConfigProvider mockPostgresConfigProvider;

  setUp(() async {
    mockPostgres = _MockPostgresBackupService();
    mockPostgresConfigProvider = _MockPostgresConfigProvider();
    if (getIt.isRegistered<IPostgresBackupService>()) {
      await getIt.unregister<IPostgresBackupService>();
    }
    getIt.registerSingleton<IPostgresBackupService>(mockPostgres);
    when(
      () => mockPostgresConfigProvider.recordConnectionTest(
        any(),
        success: any(named: 'success'),
      ),
    ).thenAnswer((_) {});
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
      FluentApp(
        locale: const Locale('en'),
        home: ChangeNotifierProvider<PostgresConfigProvider>.value(
          value: mockPostgresConfigProvider,
          child: const PostgresConfigDialog(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New PostgreSQL configuration'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
  });
}
