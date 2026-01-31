import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:result_dart/result_dart.dart';

abstract class ISqlScriptExecutionService {
  Future<Result<void>> executeScript({
    required DatabaseType databaseType,
    required SqlServerConfig? sqlServerConfig,
    required SybaseConfig? sybaseConfig,
    required PostgresConfig? postgresConfig,
    required String script,
  });
}
