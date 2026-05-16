import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_database_backup_port.dart';

abstract class ISybaseBackupService
    implements IDatabaseBackupPort<SybaseConfig> {}
