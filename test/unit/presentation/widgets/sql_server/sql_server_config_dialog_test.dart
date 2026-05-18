import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/sql_server/sql_server_config_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockSqlServerBackupService extends Mock
    implements ISqlServerBackupService {}

class _MockSqlServerConfigProvider extends Mock
    implements SqlServerConfigProvider {}

void main() {
  late _MockSqlServerBackupService mockSql;
  late _MockSqlServerConfigProvider mockSqlConfigProvider;

  setUp(() async {
    mockSql = _MockSqlServerBackupService();
    mockSqlConfigProvider = _MockSqlServerConfigProvider();
    if (getIt.isRegistered<ISqlServerBackupService>()) {
      await getIt.unregister<ISqlServerBackupService>();
    }
    getIt.registerSingleton<ISqlServerBackupService>(mockSql);
    when(
      () => mockSqlConfigProvider.recordConnectionTest(
        any(),
        success: any(named: 'success'),
      ),
    ).thenAnswer((_) {});
  });

  tearDown(() async {
    if (getIt.isRegistered<ISqlServerBackupService>()) {
      await getIt.unregister<ISqlServerBackupService>();
    }
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required SqlServerConfigDialog dialog,
  }) async {
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        home: ChangeNotifierProvider<SqlServerConfigProvider>.value(
          value: mockSqlConfigProvider,
          child: dialog,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SqlServerConfigDialog', () {
    testWidgets('shows SQL Server new configuration copy', (
      WidgetTester tester,
    ) async {
      await pumpDialog(
        tester,
        dialog: const SqlServerConfigDialog(),
      );

      expect(find.text('Authentication type'), findsOneWidget);
      expect(find.text('New SQL Server configuration'), findsOneWidget);
    });

    testWidgets(
      'does not show Sybase engine field when editing SQL config on port 2638',
      (WidgetTester tester) async {
        final config = SqlServerConfig(
          name: 'legacy',
          server: 'localhost',
          database: DatabaseName('master'),
          username: 'sa',
          password: 'x',
          port: PortNumber(2638),
        );

        await pumpDialog(
          tester,
          dialog: SqlServerConfigDialog(
            config: config,
          ),
        );

        expect(find.text('Authentication type'), findsOneWidget);
        expect(find.text('Server name (Engine Name)'), findsNothing);
      },
    );
  });
}
