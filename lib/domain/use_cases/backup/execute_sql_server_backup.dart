import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../entities/sql_server_config.dart';
import '../../../infrastructure/external/process/sql_server_backup_service.dart';

class ExecuteSqlServerBackup {
  final SqlServerBackupService _backupService;

  ExecuteSqlServerBackup(this._backupService);

  Future<rd.Result<SqlServerBackupResult>> call({
    required SqlServerConfig config,
    required String outputDirectory,
    String? customFileName,
  }) async {
    // Validações
    if (config.server.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Servidor não pode ser vazio'),
      );
    }
    if (config.database.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Nome do banco não pode ser vazio'),
      );
    }
    if (outputDirectory.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Diretório de saída não pode ser vazio'),
      );
    }

    return await _backupService.executeBackup(
      config: config,
      outputDirectory: outputDirectory,
      customFileName: customFileName,
    );
  }
}
