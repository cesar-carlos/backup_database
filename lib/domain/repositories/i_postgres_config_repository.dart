import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/repositories/i_database_config_repository.dart';

abstract class IPostgresConfigRepository
    implements IDatabaseConfigRepository<PostgresConfig> {}
