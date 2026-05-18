import 'package:backup_database/core/errors/failure.dart' hide Failure;
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class FirebirdBackupServiceStub implements IFirebirdBackupService {
  const FirebirdBackupServiceStub();

  static const String notImplementedMessage =
      'Backup Firebird ainda nao esta implementado nesta versao.';

  static const String probePendingMessage =
      'Sondagem Firebird pendente: integracao com gbak nao concluida.';

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required FirebirdConfig config,
    required BackupExecutionContext context,
  }) async {
    return const rd.Failure(
      ValidationFailure(message: notImplementedMessage),
    );
  }

  @override
  Future<rd.Result<bool>> testConnection(FirebirdConfig config) async {
    return const rd.Failure(
      ValidationFailure(message: probePendingMessage),
    );
  }

  @override
  Future<rd.Result<int>> getDatabaseSizeBytes({
    required FirebirdConfig config,
    Duration? timeout,
  }) async {
    return const rd.Failure(
      ValidationFailure(message: notImplementedMessage),
    );
  }

  @override
  Future<rd.Result<FirebirdGstatHeaderProbe>> probeGstatHeaderConnection(
    FirebirdConfig config,
  ) async {
    return const rd.Failure(
      ValidationFailure(message: probePendingMessage),
    );
  }

  @override
  Future<rd.Result<String>> getGstatHeaderVersionHint(
    FirebirdConfig config,
  ) async {
    return const rd.Success('');
  }

  @override
  Future<rd.Result<List<String>>> listDatabases({
    required FirebirdConfig config,
    Duration? timeout,
  }) async {
    return const rd.Success(<String>[]);
  }
}
