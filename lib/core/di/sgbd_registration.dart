import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/external/external.dart';
import 'package:backup_database/infrastructure/repositories/repositories.dart';
import 'package:get_it/get_it.dart';

extension SgbdRegistration on GetIt {
  void registerSgbd<
    TConfig extends DatabaseConnectionConfig,
    TData,
    TRepo extends IDatabaseConfigRepository<TConfig>,
    TPort extends IDatabaseBackupPort<TConfig>,
    TProvider extends Object
  >({
    required FactoryFunc<TRepo> repositoryBuilder,
    required FactoryFunc<TPort> portBuilder,
    required FactoryFunc<TProvider> providerBuilder,
  }) {
    registerLazySingleton<TRepo>(repositoryBuilder);
    registerLazySingleton<TPort>(portBuilder);
    registerFactory<TProvider>(providerBuilder);
  }
}

void registerBackupDatabaseDefaultSgbds(GetIt getIt) {
  getIt.registerSgbd<
    SqlServerConfig,
    SqlServerConfigsTableData,
    ISqlServerConfigRepository,
    ISqlServerBackupService,
    SqlServerConfigProvider
  >(
    repositoryBuilder: () => SqlServerConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
    portBuilder: () => SqlServerBackupService(getIt<ProcessService>()),
    providerBuilder: () => SqlServerConfigProvider(
      getIt<ISqlServerConfigRepository>(),
      getIt<IScheduleRepository>(),
      getIt<ToolVerificationService>(),
    ),
  );

  getIt.registerSgbd<
    SybaseConfig,
    SybaseConfigsTableData,
    ISybaseConfigRepository,
    ISybaseBackupService,
    SybaseConfigProvider
  >(
    repositoryBuilder: () => SybaseConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
    portBuilder: () => SybaseBackupService(
      getIt<ProcessService>(),
      strategyCache: getIt<SybaseConnectionStrategyCache>(),
    ),
    providerBuilder: () => SybaseConfigProvider(
      getIt<ISybaseConfigRepository>(),
      getIt<IScheduleRepository>(),
      getIt<ToolVerificationService>(),
    ),
  );

  getIt.registerSgbd<
    PostgresConfig,
    PostgresConfigsTableData,
    IPostgresConfigRepository,
    IPostgresBackupService,
    PostgresConfigProvider
  >(
    repositoryBuilder: () => PostgresConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
      getIt<ProcessService>(),
    ),
    portBuilder: () => PostgresBackupService(getIt<ProcessService>()),
    providerBuilder: () => PostgresConfigProvider(
      getIt<IPostgresConfigRepository>(),
      getIt<IScheduleRepository>(),
      getIt<ToolVerificationService>(),
    ),
  );

  getIt.registerSgbd<
    FirebirdConfig,
    FirebirdConfigsTableData,
    IFirebirdConfigRepository,
    IFirebirdBackupService,
    FirebirdConfigProvider
  >(
    repositoryBuilder: () => FirebirdConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
    portBuilder: () => FirebirdBackupService(getIt<ProcessService>()),
    providerBuilder: () => FirebirdConfigProvider(
      getIt<IFirebirdConfigRepository>(),
      getIt<IScheduleRepository>(),
      getIt<ToolVerificationService>(),
    ),
  );
}
