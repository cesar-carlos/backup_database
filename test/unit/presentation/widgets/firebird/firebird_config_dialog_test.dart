import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/errors/failure.dart'
    show ValidationFailure;
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:backup_database/presentation/widgets/firebird/firebird_config_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockFirebirdBackupService extends Mock
    implements IFirebirdBackupService {}

class _MockFirebirdConfigProvider extends Mock
    implements FirebirdConfigProvider {}

void main() {
  late _MockFirebirdBackupService mockFirebirdBackup;
  late _MockFirebirdConfigProvider mockFirebirdConfigProvider;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(
      FirebirdConfig(
        name: 'fb',
        host: 'localhost',
        databaseFile: r'C:\x.fdb',
        username: 'u',
        password: 'p',
      ),
    );
  });

  setUp(() async {
    mockFirebirdBackup = _MockFirebirdBackupService();
    mockFirebirdConfigProvider = _MockFirebirdConfigProvider();
    if (getIt.isRegistered<IFirebirdBackupService>()) {
      await getIt.unregister<IFirebirdBackupService>();
    }
    getIt.registerSingleton<IFirebirdBackupService>(mockFirebirdBackup);
    when(
      () => mockFirebirdBackup.listDatabases(config: any(named: 'config')),
    ).thenAnswer((_) async => const rd.Success(<String>[]));
    when(
      () => mockFirebirdConfigProvider.recordConnectionTest(
        any(),
        success: any(named: 'success'),
      ),
    ).thenAnswer((_) {});
  });

  tearDown(() async {
    if (getIt.isRegistered<IFirebirdBackupService>()) {
      await getIt.unregister<IFirebirdBackupService>();
    }
  });

  testWidgets('shows new Firebird configuration title and core fields (en)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en', 'US'),
        home: ChangeNotifierProvider<FirebirdConfigProvider>.value(
          value: mockFirebirdConfigProvider,
          child: const FirebirdConfigDialog(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Firebird configuration'), findsOneWidget);
    expect(find.text('Configuration name'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('Database file (.fdb)'), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
  });

  testWidgets('edit mode shows title and loads configuration name (en)', (
    WidgetTester tester,
  ) async {
    const configName = 'Prod FB';
    final existing = FirebirdConfig(
      id: 'fb-dialog-edit-1',
      name: configName,
      host: 'fb-host',
      databaseFile: r'C:\Data\prod.fdb',
      username: 'SYSDBA',
      password: 'secret',
      port: PortNumber(3050),
      serverVersionHint: FirebirdServerVersionHint.v30,
    );

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en', 'US'),
        home: ChangeNotifierProvider<FirebirdConfigProvider>.value(
          value: mockFirebirdConfigProvider,
          child: FirebirdConfigDialog(config: existing),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Firebird configuration'), findsOneWidget);
    expect(find.text(configName), findsOneWidget);
    expect(find.text('fb-host'), findsOneWidget);
    expect(find.text(r'C:\Data\prod.fdb'), findsOneWidget);
  });

  testWidgets(
    'Test connection shows success InfoBar with detected version (en)',
    (WidgetTester tester) async {
      when(
        () => mockFirebirdBackup.listDatabases(config: any(named: 'config')),
      ).thenAnswer(
        (_) async => const rd.Success(<String>[r'\\srv\share\warehouse.fdb']),
      );
      when(
        () => mockFirebirdBackup.probeGstatHeaderConnection(any()),
      ).thenAnswer(
        (_) async => const rd.Success((versionHint: 'ODS 12.0 (Firebird 3.x)')),
      );

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('en', 'US'),
          home: ChangeNotifierProvider<FirebirdConfigProvider>.value(
            value: mockFirebirdConfigProvider,
            child: const FirebirdConfigDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textBoxes = find.byType(TextBox);
      expect(textBoxes, findsWidgets);
      await tester.enterText(textBoxes.at(0), 'Probe FB');
      await tester.enterText(textBoxes.at(1), '127.0.0.1');
      await tester.enterText(textBoxes.at(3), r'C:\Data\app.fdb');
      await tester.enterText(textBoxes.at(5), 'SYSDBA');
      await tester.enterText(textBoxes.at(6), 'secret');

      await tester.tap(find.text('Test connection'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.textContaining('Connection tested successfully!'),
        findsWidgets,
      );
      expect(find.textContaining('Detected version:'), findsWidgets);
      expect(find.textContaining('ODS 12.0'), findsWidgets);
      expect(
        find.textContaining(r'\\srv\share\warehouse.fdb'),
        findsWidgets,
      );

      verify(
        () => mockFirebirdBackup.probeGstatHeaderConnection(any()),
      ).called(1);
      verify(
        () => mockFirebirdBackup.listDatabases(config: any(named: 'config')),
      ).called(1);
      verify(
        () => mockFirebirdConfigProvider.recordConnectionTest(
          any(),
          success: true,
        ),
      ).called(1);

      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'Test connection shows error MessageModal with probe failure message (en)',
    (WidgetTester tester) async {
      const failureMessage = 'Unable to reach database on host.';
      when(
        () => mockFirebirdBackup.probeGstatHeaderConnection(any()),
      ).thenAnswer(
        (_) async => const rd.Failure(
          ValidationFailure(message: failureMessage),
        ),
      );

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('en', 'US'),
          home: ChangeNotifierProvider<FirebirdConfigProvider>.value(
            value: mockFirebirdConfigProvider,
            child: const FirebirdConfigDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textBoxes = find.byType(TextBox);
      await tester.enterText(textBoxes.at(0), 'Probe FB');
      await tester.enterText(textBoxes.at(1), '192.168.1.10');
      await tester.enterText(textBoxes.at(3), r'C:\Data\app.fdb');
      await tester.enterText(textBoxes.at(5), 'SYSDBA');
      await tester.enterText(textBoxes.at(6), 'secret');

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(find.text('Error testing connection'), findsOneWidget);
      expect(find.textContaining(failureMessage), findsOneWidget);

      verify(
        () => mockFirebirdConfigProvider.recordConnectionTest(
          any(),
          success: false,
        ),
      ).called(1);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Test connection maps gstat not found to ToolPathHelp message (en)',
    (WidgetTester tester) async {
      when(
        () => mockFirebirdBackup.probeGstatHeaderConnection(any()),
      ).thenAnswer(
        (_) async => const rd.Failure(
          ValidationFailure(message: 'gstat: command not found'),
        ),
      );

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('en', 'US'),
          home: ChangeNotifierProvider<FirebirdConfigProvider>.value(
            value: mockFirebirdConfigProvider,
            child: const FirebirdConfigDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textBoxes = find.byType(TextBox);
      await tester.enterText(textBoxes.at(0), 'Probe FB');
      await tester.enterText(textBoxes.at(1), '127.0.0.1');
      await tester.enterText(textBoxes.at(3), r'C:\Data\app.fdb');
      await tester.enterText(textBoxes.at(5), 'SYSDBA');
      await tester.enterText(textBoxes.at(6), 'secret');

      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(find.text('Error testing connection'), findsOneWidget);
      expect(find.textContaining('gstat'), findsWidgets);
      expect(find.textContaining('PATH'), findsWidgets);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Test connection shows warning InfoBar when probe OK but listDatabases '
    'fails (en)',
    (WidgetTester tester) async {
      when(
        () => mockFirebirdBackup.probeGstatHeaderConnection(any()),
      ).thenAnswer(
        (_) async => const rd.Success((versionHint: 'ODS 12.0 (Firebird 3.x)')),
      );
      when(
        () => mockFirebirdBackup.listDatabases(config: any(named: 'config')),
      ).thenAnswer(
        (_) async => const rd.Failure(
          ValidationFailure(message: 'isql not available'),
        ),
      );

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('en', 'US'),
          home: ChangeNotifierProvider<FirebirdConfigProvider>.value(
            value: mockFirebirdConfigProvider,
            child: const FirebirdConfigDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textBoxes = find.byType(TextBox);
      await tester.enterText(textBoxes.at(0), 'Probe FB');
      await tester.enterText(textBoxes.at(1), '127.0.0.1');
      await tester.enterText(textBoxes.at(3), r'C:\Data\app.fdb');
      await tester.enterText(textBoxes.at(5), 'SYSDBA');
      await tester.enterText(textBoxes.at(6), 'secret');

      await tester.tap(find.text('Test connection'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.textContaining('Connection OK, but error resolving database'),
        findsWidgets,
      );
      expect(find.textContaining('isql not available'), findsWidgets);

      verify(
        () => mockFirebirdBackup.listDatabases(config: any(named: 'config')),
      ).called(1);
      verify(
        () => mockFirebirdConfigProvider.recordConnectionTest(
          any(),
          success: true,
        ),
      ).called(1);

      await tester.pump(const Duration(seconds: 5));
    },
  );
}
