import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class SqlServerCliRunner {
  SqlServerCliRunner(this._processService);

  final ps.ProcessService _processService;

  List<String> _baseSqlcmdArgs(SqlServerConfig config) {
    final args = <String>[
      '-S',
      '${config.server},${config.portValue}',
      '-d',
      config.databaseValue,
      '-b',
      '-r',
      '1',
    ];

    if (config.useWindowsAuth || config.username.isEmpty) {
      args.add('-E');
    } else {
      args.addAll(['-U', config.username]);
    }

    return args;
  }

  Map<String, String>? _sqlcmdEnvironment(SqlServerConfig config) {
    if (config.useWindowsAuth || config.username.isEmpty) {
      return null;
    }
    return {'SQLCMDPASSWORD': config.password};
  }

  /// Escapa o conteúdo de um identificador delimitado por colchetes
  /// (`[<identifier>]`) duplicando colchetes de fechamento.
  String escapeSqlIdentifier(String value) => value.replaceAll(']', ']]');

  /// Escapa o conteúdo de um literal string T-SQL (`N'...'`) duplicando
  /// aspas simples. Sem este escape, um nome de banco contendo `'` quebra
  /// o SQL gerado e potencialmente vira vetor de injection.
  String escapeSqlString(String value) => value.replaceAll("'", "''");

  Future<rd.Result<ps.ProcessResult>> run({
    required SqlServerConfig config,
    required List<String> extraArguments,
    required Duration timeout,
    String? tag,
  }) {
    return _processService.run(
      executable: 'sqlcmd',
      arguments: [..._baseSqlcmdArgs(config), ...extraArguments],
      environment: _sqlcmdEnvironment(config),
      timeout: timeout,
      tag: tag,
    );
  }

  /// Verifica o recovery model do banco antes de um backup de log.
  ///
  /// Retorna:
  /// - [rd.Success] quando o modo é `FULL`/`BULK_LOGGED` **ou** quando o
  ///   `sqlcmd` rodou com sucesso mas o `SELECT` voltou vazio (parsing
  ///   inconclusivo — tratado como best-effort para não bloquear
  ///   schedules cujo banco não retorna `recovery_model_desc` em
  ///   versões/configurações específicas).
  /// - [rd.Failure] quando o modo é `SIMPLE` **ou** quando a execução do
  ///   `sqlcmd` falhou (rede, credencial, timeout, exit code ≠ 0). Antes
  ///   o caminho de falha era "fail-open" (assumia FULL e prosseguia
  ///   com o `BACKUP LOG`), que então falhava mais tarde com mensagem
  ///   menos clara para o usuário.
  Future<rd.Result<void>> checkRecoveryModel(SqlServerConfig config) async {
    const query =
        'SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()';
    final result = await run(
      config: config,
      extraArguments: ['-Q', query, '-h', '-1', '-W'],
      timeout: const Duration(seconds: 10),
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          final stderr = processResult.stderr.trim();
          return rd.Failure(
            ValidationFailure(
              message:
                  'Não foi possível verificar o recovery model do banco antes '
                  'do backup de log (sqlcmd exit code '
                  '${processResult.exitCode}). Verifique credenciais, rede e '
                  'permissões do usuário SQL Server.\n'
                  '${stderr.isEmpty ? "" : "Detalhes: $stderr"}',
            ),
          );
        }
        final model = processResult.stdout.trim().toUpperCase();
        if (model.isEmpty) {
          // Inconclusive — best-effort: deixa o BACKUP LOG decidir.
          LoggerService.warning(
            'Recovery model check inconclusivo (sqlcmd OK mas stdout vazio). '
            'Prosseguindo com BACKUP LOG (best-effort).',
          );
          return const rd.Success(unit);
        }
        if (model.contains('SIMPLE')) {
          return const rd.Failure(
            ValidationFailure(
              message:
                  'Backup de log de transações não permitido: banco em modo '
                  'SIMPLE. Altere para FULL ou BULK_LOGGED.',
            ),
          );
        }
        return const rd.Success(unit);
      },
      (failure) => rd.Failure(
        ValidationFailure(
          message:
              'Não foi possível verificar o recovery model do banco antes '
              'do backup de log: ${failure is Failure ? failure.message : failure}',
          originalError: failure,
        ),
      ),
    );
  }

  /// Detecta a presença de mensagens de erro reais de SQL Server / sqlcmd
  /// na saída combinada. O matching é mais restrito do que um simples
  /// `contains('error')` para evitar falsos positivos com `RAISERROR(...)`
  /// informativos que mencionam apenas a palavra "msg".
  ///
  /// Nota: `sqlcmd -b` já retorna exit code != 0 em erros reais, portanto
  /// esta função serve como sinal redundante para detectar regressões raras
  /// (ex.: erros de severidade alta com exit code 0 em algumas builds).
  bool hasSqlcmdErrorOutput(String combinedOutputLower) {
    // Erros do servidor SQL costumam vir como
    // "Msg 3013, Level 16, State 1, Server <name>, Line N".
    // Exigimos os três marcadores juntos para reduzir falso positivo.
    final msgPattern = RegExp(r'\bmsg\s+\d+\b');
    // Antes: r'\blevel\s+1[6-9]|\blevel\s+2[0-5]\b' — sem `\b` na
    // primeira alternativa, casava "level 169" e "level 1900". Agora
    // exige fronteira de palavra após a faixa numérica.
    final levelPattern = RegExp(r'\blevel\s+(1[6-9]|2[0-5])\b');
    if (msgPattern.hasMatch(combinedOutputLower) &&
        levelPattern.hasMatch(combinedOutputLower)) {
      return true;
    }

    // Erros cliente-side do sqlcmd começam com "Sqlcmd: Error:".
    if (combinedOutputLower.contains('sqlcmd: error')) return true;

    return false;
  }

  Future<rd.Result<ps.ProcessResult>> verifyBackup({
    required SqlServerConfig config,
    required List<String> backupPaths,
    required bool enableChecksum,
    required Duration timeout,
    String? tag,
  }) {
    final fromDiskClause = backupPaths
        .map(
          (path) =>
              "FROM DISK = N'${escapeSqlString(path.replaceAll(r'\', '/'))}'",
        )
        .join(', ');
    final verifyQuery = enableChecksum
        ? 'RESTORE VERIFYONLY $fromDiskClause WITH CHECKSUM'
        : 'RESTORE VERIFYONLY $fromDiskClause';

    return run(
      config: config,
      extraArguments: ['-Q', verifyQuery],
      timeout: timeout,
      tag: tag,
    );
  }
}
