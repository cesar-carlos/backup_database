import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/services/i_database_backup_port.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IPostgresBackupService
    implements IDatabaseBackupPort<PostgresConfig> {
  Future<rd.Result<List<String>>> listDatabases({
    required PostgresConfig config,
    Duration? timeout,
  });
}
