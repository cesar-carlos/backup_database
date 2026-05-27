import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/services/i_database_backup_port.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class ISqlServerBackupService
    implements IDatabaseBackupPort<SqlServerConfig> {
  Future<rd.Result<List<String>>> listDatabases({
    required SqlServerConfig config,
    Duration? timeout,
  });
}
