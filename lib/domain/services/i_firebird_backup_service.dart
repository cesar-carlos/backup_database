import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/services/i_database_backup_port.dart';

abstract class IFirebirdBackupService
    implements IDatabaseBackupPort<FirebirdConfig> {}
