import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class PostgresBackupVerifier {
  PostgresBackupVerifier(this._processService);

  final ps.ProcessService _processService;

  Future<rd.Result<void>> verifyBackup(
    String backupPath, {
    required Duration timeout,
    String? cancelTag,
  }) async {
    final verifyArgs = ['-D', backupPath];

    final verifyResult = await _processService.run(
      executable: 'pg_verifybackup',
      arguments: verifyArgs,
      timeout: timeout,
      tag: cancelTag,
    );

    return verifyResult.fold((processResult) {
      if (processResult.isSuccess) {
        return const rd.Success(unit);
      } else {
        return rd.Failure(
          BackupFailure(
            message:
                'Verificação de integridade falhou: ${processResult.stderr}',
            originalError: Exception(processResult.stderr),
          ),
        );
      }
    }, rd.Failure.new);
  }

  Future<rd.Result<void>> verifyFullSingleBackup(
    String backupPath, {
    required Duration timeout,
    String? cancelTag,
  }) async {
    final verifyArgs = ['-l', backupPath];

    final verifyResult = await _processService.run(
      executable: 'pg_restore',
      arguments: verifyArgs,
      timeout: timeout,
      tag: cancelTag,
    );

    return verifyResult.fold((processResult) {
      if (processResult.isSuccess) {
        final objectCount = processResult.stdout
            .split('\n')
            .where((line) => line.trim().isNotEmpty && !line.startsWith(';'))
            .length;
        // `pg_restore -l` lê apenas o TOC (Table of Contents) do archive
        // em custom format. Não valida CRC de dados nem reexecuta o
        // backup, então corrupção interna em blocos de dados passa por
        // aqui despercebida. A garantia entregue é apenas que o
        // cabeçalho/TOC do .backup é legível pelo pg_restore.
        LoggerService.warning(
          'Verificação leve do backup (pg_restore -l) concluída: header/TOC '
          'válido com $objectCount objetos. Esta validação NÃO confere CRC '
          'do payload. Para garantia completa, execute um restore real em '
          'ambiente de teste.',
        );
        return const rd.Success(unit);
      } else {
        return rd.Failure(
          BackupFailure(
            message:
                'Verificação de integridade falhou: ${processResult.stderr}',
            originalError: Exception(processResult.stderr),
          ),
        );
      }
    }, rd.Failure.new);
  }
}
