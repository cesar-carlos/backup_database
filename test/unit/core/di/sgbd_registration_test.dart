import 'package:backup_database/application/providers/firebird_config_provider.dart';
import 'package:backup_database/application/providers/postgres_config_provider.dart';
import 'package:backup_database/application/providers/sql_server_config_provider.dart';
import 'package:backup_database/application/providers/sybase_config_provider.dart';
import 'package:backup_database/core/di/sgbd_registration.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/external/process/firebird_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/postgres_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/process/sql_server_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/sybase_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/sybase_connection_strategy_cache.dart';
import 'package:backup_database/infrastructure/external/process/tool_verification_service.dart';
import 'package:backup_database/infrastructure/repositories/firebird_config_repository.dart';
import 'package:backup_database/infrastructure/repositories/postgres_config_repository.dart';
import 'package:backup_database/infrastructure/repositories/sql_server_config_repository.dart';
import 'package:backup_database/infrastructure/repositories/sybase_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockPostgresRepo extends Mock implements IPostgresConfigRepository {}

class _MockPostgresPort extends Mock implements IPostgresBackupService {}

class _MockProcessService extends Mock implements ProcessService {}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockSecureCredentialService extends Mock
    implements ISecureCredentialService {}

class _TestUiProvider {}

void main() {
  late GetIt sl;

  setUp(() {
    sl = GetIt.asNewInstance();
  });

  tearDown(() async {
    await sl.reset();
  });

  test('registerSgbd registers repository, backup port and provider', () {
    final repo = _MockPostgresRepo();
    final port = _MockPostgresPort();
    sl.registerSgbd<
      PostgresConfig,
      void,
      IPostgresConfigRepository,
      IPostgresBackupService,
      _TestUiProvider
    >(
      repositoryBuilder: () => repo,
      portBuilder: () => port,
      providerBuilder: _TestUiProvider.new,
    );

    expect(sl<IPostgresConfigRepository>(), same(repo));
    expect(sl<IPostgresBackupService>(), same(port));
    expect(sl<_TestUiProvider>(), isA<_TestUiProvider>());
  });

  test('registerSgbd provider factory creates new instance each resolve', () {
    sl.registerSgbd<
      PostgresConfig,
      void,
      IPostgresConfigRepository,
      IPostgresBackupService,
      _TestUiProvider
    >(
      repositoryBuilder: _MockPostgresRepo.new,
      portBuilder: _MockPostgresPort.new,
      providerBuilder: _TestUiProvider.new,
    );

    final first = sl<_TestUiProvider>();
    final second = sl<_TestUiProvider>();
    expect(identical(first, second), isFalse);
  });

  test(
    'registerBackupDatabaseDefaultSgbds registers concrete repos and '
    'backup ports',
    () async {
      final appDatabase = AppDatabase.inMemory();
      final secureCredentialService = _MockSecureCredentialService();
      final processService = _MockProcessService();
      final scheduleRepository = _MockScheduleRepository();

      when(
        () => processService.run(
          executable: any(named: 'executable'),
          arguments: any(named: 'arguments'),
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
          timeout: any(named: 'timeout'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer(
        (_) async => const rd.Success(
          ProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: '',
            duration: Duration.zero,
          ),
        ),
      );

      try {
        sl
          ..registerSingleton<AppDatabase>(appDatabase)
          ..registerSingleton<ISecureCredentialService>(
            secureCredentialService,
          )
          ..registerSingleton<ProcessService>(processService)
          ..registerSingleton<SybaseConnectionStrategyCache>(
            SybaseConnectionStrategyCache(),
          )
          ..registerSingleton<IScheduleRepository>(scheduleRepository)
          ..registerSingleton<ToolVerificationService>(
            ToolVerificationService(processService),
          );

        registerBackupDatabaseDefaultSgbds(sl);

        expect(
          sl<ISqlServerConfigRepository>(),
          isA<SqlServerConfigRepository>(),
        );
        expect(sl<ISqlServerBackupService>(), isA<SqlServerBackupService>());

        expect(sl<ISybaseConfigRepository>(), isA<SybaseConfigRepository>());
        expect(sl<ISybaseBackupService>(), isA<SybaseBackupService>());

        expect(
          sl<IPostgresConfigRepository>(),
          isA<PostgresConfigRepository>(),
        );
        expect(sl<IPostgresBackupService>(), isA<PostgresBackupService>());

        expect(
          sl<IFirebirdConfigRepository>(),
          isA<FirebirdConfigRepository>(),
        );

        expect(sl<SqlServerConfigProvider>(), isA<SqlServerConfigProvider>());
        expect(sl<SybaseConfigProvider>(), isA<SybaseConfigProvider>());
        expect(sl<PostgresConfigProvider>(), isA<PostgresConfigProvider>());
        expect(sl<FirebirdConfigProvider>(), isA<FirebirdConfigProvider>());

        expect(
          sl<IFirebirdBackupService>(),
          isA<FirebirdBackupService>(),
        );
      } finally {
        await appDatabase.close();
      }
    },
  );
}
