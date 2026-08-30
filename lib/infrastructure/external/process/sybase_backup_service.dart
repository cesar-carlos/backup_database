import 'dart:async';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/string_field_validator.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:backup_database/infrastructure/external/process/sybase/sybase_backup_executor.dart';
import 'package:backup_database/infrastructure/external/process/sybase/sybase_cli_runner.dart';
import 'package:backup_database/infrastructure/external/process/sybase/sybase_failure_message.dart';
import 'package:backup_database/infrastructure/external/process/sybase/sybase_verification_runner.dart';
import 'package:backup_database/infrastructure/external/process/sybase_connection_strategy_cache.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SybaseBackupService implements ISybaseBackupService {
  SybaseBackupService(
    ps.ProcessService processService, {
    required this._strategyCache,
    bool useCredentialsFile = true,
  }) : _cliRunner = SybaseCliRunner(
         processService: processService,
         useCredentialsFile: useCredentialsFile,
       ) {
    // A6: limpa eventuais diretórios `sybase_backup_*` deixados em
    // `Directory.systemTemp` por execuções anteriores que foram mortas
    // antes do `finally` do `_runSybaseToolWithCredentials`. Cada um
    // contém um `args.txt` com `PWD=...` em texto plano. O cleanup é
    // best-effort e roda em background — falhas são logadas em debug.
    unawaited(_cliRunner.cleanupOrphanCredentialDirs());
  }

  final SybaseConnectionStrategyCache _strategyCache;
  final SybaseCliRunner _cliRunner;
  late final SybaseVerificationRunner _verificationRunner =
      SybaseVerificationRunner(cliRunner: _cliRunner);
  late final SybaseBackupExecutor _executor = SybaseBackupExecutor(
    cliRunner: _cliRunner,
    strategyCache: _strategyCache,
    verificationRunner: _verificationRunner,
  );

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required SybaseConfig config,
    required BackupExecutionContext context,
  }) {
    return _executor.executeBackupCore(
      config: config,
      outputDirectory: context.outputDirectory,
      backupType: context.backupType,
      customFileName: context.customFileName,
      dbbackupPath: context.dbbackupPath,
      truncateLog: context.truncateLog,
      verifyAfterBackup: context.verifyAfterBackup,
      verifyPolicy: context.verifyPolicy,
      backupTimeout: context.backupTimeout,
      verifyTimeout: context.verifyTimeout,
      sybaseBackupOptions: context.sybaseBackupOptions,
      cancelTag: context.cancelTag,
    );
  }

  @override
  Future<rd.Result<bool>> testConnection(SybaseConfig config) async {
    try {
      LoggerService.info(
        'Testando conexão Sybase: Engine=${config.serverName}, DBN=${config.databaseNameValue}',
      );

      // Antes: 3 `if (X.trim().isEmpty) return rd.Failure(BackupFailure(...))`
      // empilhados (~18 linhas). `StringFieldValidator.requireAllNonBlank`
      // retorna `ValidationFailure?` — semanticamente mais correto que
      // `BackupFailure` para erros de validação de input (mas
      // `Result<bool>` aceita qualquer subclasse de `Failure`, então
      // não há regressão para callers).
      final validation = StringFieldValidator.requireAllNonBlank({
        'Nome do servidor (Engine Name)': config.serverName,
        'Nome do banco de dados (DBN)': config.databaseNameValue,
        'Usuário': config.username,
      });
      if (validation != null) return rd.Failure(validation);

      final databaseName = config.databaseNameValue;
      // C4: reusa a mesma fonte de estratégias do backup (sem duplicação
      // da composição de connection string).
      final strategies = SybaseBackupExecutor.buildDbisqlStrategies(
        config,
        databaseName,
      );
      // Tag de processo para permitir que o orchestrator/painel de
      // diagnóstico identifique probes de teste de conexão e os agrupe
      // separadamente dos backups de produção.
      final probeTag = 'sybase-test-conn-${config.id}';

      var lastError = '';

      for (var i = 0; i < strategies.length; i++) {
        final connStr = strategies[i].conn;
        try {
          LoggerService.debug(
            'Tentando teste de conexão com estratégia '
            '${i + 1}/${strategies.length}',
          );

          final arguments = ['-c', connStr, '-q', 'SELECT 1', '-nogui'];

          final result = await _cliRunner.runWithCredentials(
            executable: 'dbisql',
            arguments: arguments,
            // Antes era 10s, apertado para servidor remoto/VPN. Postgres
            // já usa 30s; alinhamos para o mesmo limite e reduzimos
            // falsos negativos em redes lentas.
            timeout: const Duration(seconds: 30),
            tag: probeTag,
          );

          final success = result.fold(
            (processResult) => processResult.isSuccess,
            (failure) => false,
          );

          if (success) {
            LoggerService.info('Teste de conexão Sybase bem-sucedido');
            return const rd.Success(true);
          }

          result.fold(
            (processResult) {
              final combinedOutput =
                  '${processResult.stdout}\n${processResult.stderr}'.trim();
              lastError = combinedOutput.isNotEmpty
                  ? combinedOutput
                  : 'Falha na conexão (Exit Code: ${processResult.exitCode})';
              LoggerService.debug('Estratégia falhou: $lastError');
            },
            (failure) {
              lastError = sybaseFailureMessage(failure);
              LoggerService.debug('Estratégia falhou: $lastError');
            },
          );
        } on Object catch (e) {
          lastError = e.toString();
          LoggerService.debug('Erro ao testar estratégia: $lastError');
        }
      }

      var errorMessage = 'Não foi possível conectar ao banco de dados Sybase';

      if (lastError.isNotEmpty) {
        final errorLower = lastError.toLowerCase();
        if (errorLower.contains('path_setup') ||
            errorLower.contains('instruções')) {
          errorMessage = lastError;
        } else if (SybaseBackupExecutor.looksLikeToolNotFound(errorLower)) {
          // Mesma melhoria do `_buildNoStrategyWorkedMessage`: stderr EN
          // do shell ("'dbisql' is not recognized as an internal or
          // external command") agora vira mensagem orientada do
          // `ToolPathHelp`.
          final missingTool =
              ToolPathHelp.isToolNotFoundError(
                errorLower,
                'dbbackup',
              )
              ? 'dbbackup'
              : 'dbisql';
          errorMessage = ToolPathHelp.buildMessage(missingTool);
        } else if (errorLower.contains('unable to connect') ||
            errorLower.contains('server not found') ||
            errorLower.contains('connection refused') ||
            errorLower.contains('connection timed out')) {
          errorMessage =
              'Não foi possível conectar ao servidor Sybase. Verifique:\n'
              '1. Se o servidor está rodando\n'
              '2. Se o Engine Name (${config.serverName}) está correto\n'
              '3. Se o DBN (${config.databaseNameValue}) está correto\n'
              '4. Se a porta (${config.portValue}) está correta';
        } else if (errorLower.contains('invalid user') ||
            errorLower.contains('login failed')) {
          errorMessage = 'Usuário ou senha inválidos.';
        } else if (errorLower.contains('already in use')) {
          errorMessage = 'O banco de dados está em uso. Verifique se o Engine Name está correto.';
        } else {
          errorMessage =
              'Erro ao conectar: $lastError\n\n'
              'Verifique na página de configuração se dbisql está disponível.';
        }
      }

      LoggerService.warning(
        'Todas as estratégias de teste de conexão falharam',
      );
      return rd.Failure(NetworkFailure(message: errorMessage));
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao testar conexão Sybase', e, stackTrace);
      return rd.Failure(
        NetworkFailure(
          message: 'Erro ao testar conexão Sybase: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<int>> getDatabaseSizeBytes({
    required SybaseConfig config,
    Duration? timeout,
  }) async {
    final databaseName = config.databaseNameValue;
    final connStr =
        'ENG=${config.serverName};DBN=$databaseName;'
        'UID=${config.username};PWD=${config.password}';
    // db_property('FileSize') retorna o tamanho do arquivo principal em
    // páginas; multiplicamos por PageSize para chegar em bytes.
    const sql =
        "SELECT CAST(db_property('FileSize') AS BIGINT) * "
        "CAST(db_property('PageSize') AS BIGINT)";

    final result = await _cliRunner.runWithCredentials(
      executable: 'dbisql',
      arguments: ['-c', connStr, '-nogui', '-q', sql],
      timeout: timeout ?? const Duration(seconds: 15),
      tag: 'sybase-size-${config.id}',
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Não foi possível obter tamanho do banco Sybase: '
                  '${processResult.stderr}',
            ),
          );
        }
        final raw = processResult.stdout
            .split(RegExp(r'[\r\n]+'))
            .map((l) => l.trim())
            .firstWhere(
              (l) => l.isNotEmpty && int.tryParse(l) != null,
              orElse: () => '',
            );
        final size = int.tryParse(raw);
        if (size == null) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Resposta inválida ao consultar tamanho do banco Sybase: '
                  '${processResult.stdout}',
            ),
          );
        }
        return rd.Success(size);
      },
      rd.Failure.new,
    );
  }
}
