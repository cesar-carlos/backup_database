import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/repositories/i_database_config_repository.dart';

abstract class ISqlServerConfigRepository
    implements IDatabaseConfigRepository<SqlServerConfig> {}
