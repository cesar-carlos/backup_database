import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/repositories/i_database_config_repository.dart';

abstract class IFirebirdConfigRepository
    implements IDatabaseConfigRepository<FirebirdConfig> {}
