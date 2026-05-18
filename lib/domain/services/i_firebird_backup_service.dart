import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/services/i_database_backup_port.dart';
import 'package:result_dart/result_dart.dart';

typedef FirebirdGstatHeaderProbe = ({String versionHint});

abstract class IFirebirdBackupService
    implements IDatabaseBackupPort<FirebirdConfig> {
  Future<Result<FirebirdGstatHeaderProbe>> probeGstatHeaderConnection(
    FirebirdConfig config,
  );

  Future<Result<String>> getGstatHeaderVersionHint(FirebirdConfig config);

  Future<Result<List<String>>> listDatabases({
    required FirebirdConfig config,
    Duration? timeout,
  });
}
