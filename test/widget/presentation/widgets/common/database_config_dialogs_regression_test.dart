import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/presentation/widgets/firebird/firebird_config_dialog.dart';
import 'package:backup_database/presentation/widgets/organisms/database_config_dialog_shell.dart';
import 'package:backup_database/presentation/widgets/postgres/postgres_config_dialog.dart';
import 'package:backup_database/presentation/widgets/sql_server/sql_server_config_dialog.dart';
import 'package:backup_database/presentation/widgets/sybase/sybase_config_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSqlServerBackupService extends Mock
    implements ISqlServerBackupService {}

class _MockPostgresBackupService extends Mock
    implements IPostgresBackupService {}

class _MockSybaseBackupService extends Mock implements ISybaseBackupService {}

class _MockFirebirdBackupService extends Mock
    implements IFirebirdBackupService {}

class _MockSqlConfigProvider extends Mock implements SqlServerConfigProvider {}

class _MockPostgresConfigProvider extends Mock
    implements PostgresConfigProvider {}

class _MockSybaseConfigProvider extends Mock implements SybaseConfigProvider {}

class _MockFirebirdConfigProvider extends Mock
    implements FirebirdConfigProvider {}

void main() {
  late _MockSqlServerBackupService mockSql;
  late _MockPostgresBackupService mockPostgres;
  late _MockSybaseBackupService mockSybase;
  late _MockFirebirdBackupService mockFirebird;
  late _MockSqlConfigProvider mockSqlConfigProvider;
  late _MockPostgresConfigProvider mockPostgresConfigProvider;
  late _MockSybaseConfigProvider mockSybaseConfigProvider;
  late _MockFirebirdConfigProvider mockFirebirdConfigProvider;

  setUp(() async {
    mockSql = _MockSqlServerBackupService();
    mockPostgres = _MockPostgresBackupService();
    mockSybase = _MockSybaseBackupService();
    mockFirebird = _MockFirebirdBackupService();
    mockSqlConfigProvider = _MockSqlConfigProvider();
    mockPostgresConfigProvider = _MockPostgresConfigProvider();
    mockSybaseConfigProvider = _MockSybaseConfigProvider();
    mockFirebirdConfigProvider = _MockFirebirdConfigProvider();
    when(
      () => mockSqlConfigProvider.recordConnectionTest(
        any(),
        success: any(named: 'success'),
      ),
    ).thenAnswer((_) {});
    when(
      () => mockPostgresConfigProvider.recordConnectionTest(
        any(),
        success: any(named: 'success'),
      ),
    ).thenAnswer((_) {});
    when(
      () => mockSybaseConfigProvider.recordConnectionTest(
        any(),
        success: any(named: 'success'),
      ),
    ).thenAnswer((_) {});
    when(
      () => mockFirebirdConfigProvider.recordConnectionTest(
        any(),
        success: any(named: 'success'),
      ),
    ).thenAnswer((_) {});
    if (getIt.isRegistered<ISqlServerBackupService>()) {
      await getIt.unregister<ISqlServerBackupService>();
    }
    getIt.registerSingleton<ISqlServerBackupService>(mockSql);
    if (getIt.isRegistered<IPostgresBackupService>()) {
      await getIt.unregister<IPostgresBackupService>();
    }
    getIt.registerSingleton<IPostgresBackupService>(mockPostgres);
    if (getIt.isRegistered<IFirebirdBackupService>()) {
      await getIt.unregister<IFirebirdBackupService>();
    }
    getIt.registerSingleton<IFirebirdBackupService>(mockFirebird);
  });

  tearDown(() async {
    if (getIt.isRegistered<ISqlServerBackupService>()) {
      await getIt.unregister<ISqlServerBackupService>();
    }
    if (getIt.isRegistered<IPostgresBackupService>()) {
      await getIt.unregister<IPostgresBackupService>();
    }
    if (getIt.isRegistered<IFirebirdBackupService>()) {
      await getIt.unregister<IFirebirdBackupService>();
    }
  });

  Future<void> pumpDialog(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('D5 database config dialogs regression', () {
    testWidgets('SqlServerConfigDialog uses shell and SQL-only copy', (
      WidgetTester tester,
    ) async {
      await pumpDialog(
        tester,
        ChangeNotifierProvider<SqlServerConfigProvider>.value(
          value: mockSqlConfigProvider,
          child: const SqlServerConfigDialog(),
        ),
      );

      expect(find.byType(DatabaseConfigDialogShell), findsOneWidget);
      expect(find.text('New SQL Server configuration'), findsOneWidget);
      expect(find.text('Authentication type'), findsOneWidget);
      expect(find.text('Server name (Engine Name)'), findsNothing);
      expect(find.text('Host'), findsNothing);
    });

    testWidgets('PostgresConfigDialog uses shell and Postgres-only copy', (
      WidgetTester tester,
    ) async {
      await pumpDialog(
        tester,
        ChangeNotifierProvider<PostgresConfigProvider>.value(
          value: mockPostgresConfigProvider,
          child: const PostgresConfigDialog(),
        ),
      );

      expect(find.byType(DatabaseConfigDialogShell), findsOneWidget);
      expect(find.text('New PostgreSQL configuration'), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
      expect(find.text('Authentication type'), findsNothing);
      expect(find.text('Server name (Engine Name)'), findsNothing);
    });

    testWidgets('SybaseConfigDialog uses shell and Sybase-only copy', (
      WidgetTester tester,
    ) async {
      await pumpDialog(
        tester,
        ChangeNotifierProvider<SybaseConfigProvider>.value(
          value: mockSybaseConfigProvider,
          child: SybaseConfigDialog(backupService: mockSybase),
        ),
      );

      expect(find.byType(DatabaseConfigDialogShell), findsOneWidget);
      expect(find.text('New Sybase configuration'), findsOneWidget);
      expect(find.text('Server name (Engine Name)'), findsOneWidget);
      expect(find.text('Authentication type'), findsNothing);
      expect(find.text('Host'), findsNothing);
    });

    testWidgets('FirebirdConfigDialog uses shell and Firebird-only copy', (
      WidgetTester tester,
    ) async {
      await pumpDialog(
        tester,
        ChangeNotifierProvider<FirebirdConfigProvider>.value(
          value: mockFirebirdConfigProvider,
          child: const FirebirdConfigDialog(),
        ),
      );

      expect(find.byType(DatabaseConfigDialogShell), findsOneWidget);
      expect(find.text('New Firebird configuration'), findsOneWidget);
      expect(find.text('Database file (.fdb)'), findsOneWidget);
      expect(find.text('Authentication type'), findsNothing);
      expect(find.text('Test connection'), findsOneWidget);
    });
  });
}
