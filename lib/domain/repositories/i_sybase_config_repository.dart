import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/repositories/i_database_config_repository.dart';

abstract class ISybaseConfigRepository
    implements IDatabaseConfigRepository<SybaseConfig> {}
