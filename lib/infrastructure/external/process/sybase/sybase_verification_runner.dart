import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/infrastructure/external/process/sybase/sybase_cli_runner.dart';
import 'package:backup_database/infrastructure/external/process/sybase/sybase_failure_message.dart';
import 'package:backup_database/infrastructure/external/process/sybase/sybase_verify_outcome.dart';
import 'package:path/path.dart' as p;

class SybaseVerificationRunner {
  SybaseVerificationRunner({required this._cliRunner});

  final SybaseCliRunner _cliRunner;

  /// Roda a verificação pós-backup (dbvalid + fallback dbverify) ou
  /// determina que verificação não é aplicável (log).
  ///
  /// Para `effectiveType == log`, retorna outcome de log indisponível e
  /// (em strict) sinaliza falha via `strictFailureMessage` para o caller
  /// abortar antes de montar métricas.
  Future<SybaseVerifyOutcome> runVerification({
    required SybaseConfig config,
    required String actualBackupPath,
    required BackupType effectiveType,
    required bool verifyAfterBackup,
    required VerifyPolicy verifyPolicy,
    required Duration? verifyTimeout,
    required String verifyCancelTag,
  }) async {
    if (!verifyAfterBackup) {
      return const SybaseVerifyOutcome(
        success: false,
        methodUsed: 'dbvalid',
        duration: Duration.zero,
      );
    }

    if (effectiveType == BackupType.log) {
      // C6: strict + log = decisão explícita de "não há verificação real
      // disponível para log". Em strict, sinalizamos falha via mensagem.
      if (verifyPolicy == VerifyPolicy.strict) {
        return const SybaseVerifyOutcome(
          success: false,
          methodUsed: 'dbvalid',
          duration: Duration.zero,
          strictFailureMessage:
              'Verificação de integridade não disponível para backup '
              'de log Sybase, e modo estrito (strict) foi solicitado. '
              'Use VerifyPolicy.bestEffort para backups de log ou '
              'desabilite "Verificar após backup".',
        );
      }
      LoggerService.info(
        'Verificação não disponível para backup de log; '
        'resultado registrado como indisponível',
      );
      return const SybaseVerifyOutcome(
        success: false,
        methodUsed: 'dbvalid',
        duration: Duration.zero,
      );
    }

    // M2: stopwatch só roda quando há verificação real (full).
    final stopwatch = Stopwatch()..start();
    LoggerService.info('Verificando integridade do backup Sybase...');

    var verifySuccess = false;
    var methodUsed = 'dbvalid';
    var lastVerifyError = '';

    final dir = Directory(actualBackupPath);
    if (await dir.exists()) {
      final backupDbFile = await _tryFindBackupDbFile(dir);
      if (backupDbFile != null) {
        final connStr =
            'UID=${config.username};PWD=${config.password};'
            'DBF=${backupDbFile.path}';

        final dbvalidOutcome = await _runVerifyTool(
          executable: 'dbvalid',
          connectionString: connStr,
          timeout: verifyTimeout,
          tag: verifyCancelTag,
        );
        verifySuccess = dbvalidOutcome.success;
        lastVerifyError = dbvalidOutcome.errorMessage;

        if (!verifySuccess) {
          LoggerService.debug(
            'Tentando fallback dbverify no arquivo: ${backupDbFile.path}',
          );
          final dbverifyOutcome = await _runVerifyTool(
            executable: 'dbverify',
            connectionString: connStr,
            timeout: verifyTimeout,
            tag: verifyCancelTag,
          );
          if (dbverifyOutcome.success) {
            verifySuccess = true;
            methodUsed = 'dbverify';
          } else {
            lastVerifyError = dbverifyOutcome.errorMessage;
          }
        }
      } else {
        lastVerifyError =
            'Não foi possível localizar um arquivo .db no diretório do backup';
      }
    }

    if (!verifySuccess) {
      LoggerService.warning(
        'Verificação de integridade falhou (dbvalid e dbverify): '
        '$lastVerifyError',
      );
      if (verifyPolicy == VerifyPolicy.strict) {
        stopwatch.stop();
        return SybaseVerifyOutcome(
          success: false,
          methodUsed: methodUsed,
          duration: stopwatch.elapsed,
          strictFailureMessage:
              'Verificação de integridade falhou (modo estrito). '
              '$lastVerifyError',
        );
      }
    }
    stopwatch.stop();
    return SybaseVerifyOutcome(
      success: verifySuccess,
      methodUsed: methodUsed,
      duration: stopwatch.elapsed,
    );
  }

  /// Executa um único utilitário de verificação (`dbvalid` ou `dbverify`)
  /// e devolve sucesso + mensagem de erro consolidada.
  Future<SybaseVerifyToolOutcome> _runVerifyTool({
    required String executable,
    required String connectionString,
    required Duration? timeout,
    required String tag,
  }) async {
    final result = await _cliRunner.runWithCredentials(
      executable: executable,
      arguments: ['-c', connectionString],
      timeout: timeout ?? const Duration(minutes: 30),
      tag: tag,
    );
    return result.fold(
      (processResult) {
        if (processResult.isSuccess) {
          LoggerService.info(
            'Verificação de integridade concluída com sucesso ($executable)',
          );
          return const SybaseVerifyToolOutcome(
            success: true,
            errorMessage: '',
          );
        }
        final msg = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;
        LoggerService.debug('$executable falhou: $msg');
        return SybaseVerifyToolOutcome(success: false, errorMessage: msg);
      },
      (failure) => SybaseVerifyToolOutcome(
        success: false,
        errorMessage: sybaseFailureMessage(failure),
      ),
    );
  }

  Future<File?> _tryFindBackupDbFile(Directory backupDir) async {
    try {
      final entities = await backupDir.list().toList();
      final dbFiles = entities
          .whereType<File>()
          .where((f) => p.extension(f.path).toLowerCase() == '.db')
          .toList();
      if (dbFiles.isEmpty) return null;

      // A7: `length()` async em vez de `lengthSync()` no comparador.
      final pairs = await Future.wait(
        dbFiles.map((f) async => (f, await f.length())),
      );
      pairs.sort((a, b) => b.$2.compareTo(a.$2));
      return pairs.first.$1;
    } on Object catch (_) {
      return null;
    }
  }
}
