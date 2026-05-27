import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:backup_database/domain/entities/sybase_tools_status.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ToolVerificationService {
  ToolVerificationService(this._processService);
  final ProcessService _processService;

  Future<rd.Result<bool>> verifySqlCmd() async {
    try {
      LoggerService.info('Verificando se sqlcmd está disponível...');

      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      return result.fold(
        (processResult) {
          if (processResult.isSuccess) {
            LoggerService.info('sqlcmd encontrado e disponível');
            return const rd.Success(true);
          } else {
            LoggerService.warning(
              'sqlcmd não encontrado (exit code: ${processResult.exitCode})',
            );
            return const rd.Failure(
              ValidationFailure(
                message:
                    'sqlcmd não está disponível no PATH do sistema.\n\n'
                    'Para fazer backup de SQL Server, você precisa:\n'
                    '1. Instalar SQL Server Command Line Tools\n'
                    '2. Adicionar o caminho ao PATH do Windows\n\n'
                    r'Consulte: docs\path_setup.md',
              ),
            );
          }
        },
        (failure) {
          final errorMessage = failure is Failure
              ? failure.message
              : failure.toString();
          LoggerService.warning('Erro ao verificar sqlcmd: $errorMessage');
          return const rd.Failure(
            ValidationFailure(
              message:
                  'sqlcmd não está disponível no PATH do sistema.\n\n'
                  'Para fazer backup de SQL Server, você precisa:\n'
                  '1. Instalar SQL Server Command Line Tools\n'
                  '2. Adicionar o caminho ao PATH do Windows\n\n'
                  r'Consulte: docs\path_setup.md',
            ),
          );
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar sqlcmd', e, stackTrace);
      return rd.Failure(
        ValidationFailure(
          message:
              'Erro ao verificar sqlcmd: $e\n\n'
              'Para fazer backup de SQL Server, você precisa:\n'
              '1. Instalar SQL Server Command Line Tools\n'
              '2. Adicionar o caminho ao PATH do Windows\n\n'
              r'Consulte: docs\path_setup.md',
        ),
      );
    }
  }

  Future<rd.Result<bool>> verifySybaseTools() async {
    try {
      LoggerService.info(
        'Verificando se ferramentas Sybase estão disponíveis...',
      );

      var dbisqlFound = false;
      var dbbackupFound = false;
      var dbvalidFound = false;

      final dbisqlResult = await _processService.run(
        executable: 'dbisql',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      dbisqlResult.fold((processResult) {
        if (processResult.isSuccess) {
          dbisqlFound = true;
          LoggerService.info('dbisql encontrado e disponível');
        }
      }, (_) {});

      final dbbackupResult = await _processService.run(
        executable: 'dbbackup',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      dbbackupResult.fold((processResult) {
        if (processResult.isSuccess) {
          dbbackupFound = true;
          LoggerService.info('dbbackup encontrado e disponível');
        }
      }, (_) {});

      final dbvalidResult = await _processService.run(
        executable: 'dbvalid',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      dbvalidResult.fold(
        (processResult) {
          if (processResult.isSuccess) {
            dbvalidFound = true;
            LoggerService.info('dbvalid encontrado e disponível');
          } else {
            LoggerService.debug(
              'dbvalid não encontrado (recomendado para verificação de backup)',
            );
          }
        },
        (_) {
          LoggerService.debug(
            'dbvalid não encontrado (recomendado para verificação de backup)',
          );
        },
      );

      if (dbisqlFound || dbbackupFound) {
        LoggerService.info(
          'Ferramentas Sybase encontradas: dbisql=$dbisqlFound, '
          'dbbackup=$dbbackupFound, dbvalid=$dbvalidFound',
        );
        return const rd.Success(true);
      }

      LoggerService.warning('Ferramentas Sybase não encontradas');
      return const rd.Failure(
        ValidationFailure(
          message:
              'Ferramentas Sybase não estão disponíveis no PATH do sistema.\n\n'
              'Para fazer backup de Sybase SQL Anywhere, você precisa:\n'
              '1. Instalar Sybase SQL Anywhere\n'
              '2. Adicionar o caminho Bin64 ao PATH do Windows\n'
              '   (ex: C:\\Program Files\\SQL Anywhere 16\\Bin64)\n\n'
              r'Consulte: docs\path_setup.md',
        ),
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao verificar ferramentas Sybase',
        e,
        stackTrace,
      );
      return rd.Failure(
        ValidationFailure(
          message:
              'Erro ao verificar ferramentas Sybase: $e\n\n'
              'Para fazer backup de Sybase SQL Anywhere, você precisa:\n'
              '1. Instalar Sybase SQL Anywhere\n'
              '2. Adicionar o caminho Bin64 ao PATH do Windows\n\n'
              r'Consulte: docs\path_setup.md',
        ),
      );
    }
  }

  Future<rd.Result<SybaseToolsStatus>> verifySybaseToolsDetailed() async {
    try {
      LoggerService.info(
        'Verificando estado das ferramentas Sybase...',
      );

      var dbisqlStatus = SybaseToolStatus.missing;
      var dbbackupStatus = SybaseToolStatus.missing;
      var dbvalidStatus = SybaseToolStatus.warning;
      var dbverifyStatus = SybaseToolStatus.warning;

      final dbisqlResult = await _processService.run(
        executable: 'dbisql',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      dbisqlResult.fold((processResult) {
        dbisqlStatus = processResult.isSuccess
            ? SybaseToolStatus.ok
            : SybaseToolStatus.missing;
      }, (_) {});

      final dbbackupResult = await _processService.run(
        executable: 'dbbackup',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      dbbackupResult.fold((processResult) {
        dbbackupStatus = processResult.isSuccess
            ? SybaseToolStatus.ok
            : SybaseToolStatus.missing;
      }, (_) {});

      final dbvalidResult = await _processService.run(
        executable: 'dbvalid',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      dbvalidResult.fold((processResult) {
        dbvalidStatus = processResult.isSuccess
            ? SybaseToolStatus.ok
            : SybaseToolStatus.warning;
      }, (_) {});

      final dbverifyResult = await _processService.run(
        executable: 'dbverify',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      dbverifyResult.fold((processResult) {
        dbverifyStatus = processResult.isSuccess
            ? SybaseToolStatus.ok
            : SybaseToolStatus.warning;
      }, (_) {});

      final status = SybaseToolsStatus(
        dbisql: dbisqlStatus,
        dbbackup: dbbackupStatus,
        dbvalid: dbvalidStatus,
        dbverify: dbverifyStatus,
      );

      LoggerService.info(
        'Ferramentas Sybase: dbisql=${dbisqlStatus.name}, '
        'dbbackup=${dbbackupStatus.name}, dbvalid=${dbvalidStatus.name}, '
        'dbverify=${dbverifyStatus.name}',
      );

      return rd.Success(status);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao verificar ferramentas Sybase',
        e,
        stackTrace,
      );
      return rd.Failure(
        ValidationFailure(
          message:
              'Erro ao verificar ferramentas Sybase: $e\n\n'
              'Para fazer backup de Sybase SQL Anywhere, você precisa:\n'
              '1. Instalar Sybase SQL Anywhere\n'
              '2. Adicionar o caminho Bin64 ao PATH do Windows\n\n'
              r'Consulte: docs\path_setup.md',
        ),
      );
    }
  }

  Future<rd.Result<bool>> verifyPsql() async {
    try {
      LoggerService.info('Verificando se psql está disponível...');

      final result = await _processService.run(
        executable: 'psql',
        arguments: ['--version'],
        timeout: const Duration(seconds: 5),
      );

      return result.fold(
        (processResult) {
          if (processResult.isSuccess) {
            LoggerService.info('psql encontrado e disponível');
            return const rd.Success(true);
          } else {
            LoggerService.warning(
              'psql não encontrado (exit code: ${processResult.exitCode})',
            );
            return const rd.Failure(
              ValidationFailure(
                message:
                    'psql não está disponível no PATH do sistema.\n\n'
                    'Para fazer backup de PostgreSQL, você precisa:\n'
                    '1. Instalar PostgreSQL (inclui psql)\n'
                    '2. Adicionar o caminho bin ao PATH do Windows\n'
                    '   (ex: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
                    r'Consulte: docs\path_setup.md',
              ),
            );
          }
        },
        (failure) {
          final errorMessage = failure is Failure
              ? failure.message
              : failure.toString();
          LoggerService.warning('Erro ao verificar psql: $errorMessage');
          return const rd.Failure(
            ValidationFailure(
              message:
                  'psql não está disponível no PATH do sistema.\n\n'
                  'Para fazer backup de PostgreSQL, você precisa:\n'
                  '1. Instalar PostgreSQL (inclui psql)\n'
                  '2. Adicionar o caminho bin ao PATH do Windows\n'
                  '   (ex: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
                  r'Consulte: docs\path_setup.md',
            ),
          );
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar psql', e, stackTrace);
      return rd.Failure(
        ValidationFailure(
          message:
              'Erro ao verificar psql: $e\n\n'
              'Para fazer backup de PostgreSQL, você precisa:\n'
              '1. Instalar PostgreSQL (inclui psql)\n'
              '2. Adicionar o caminho bin ao PATH do Windows\n\n'
              r'Consulte: docs\path_setup.md',
        ),
      );
    }
  }

  Future<rd.Result<bool>> verifyPgBasebackup() async {
    LoggerService.info('Verificando se pg_basebackup está disponível...');

    final result = await _processService.run(
      executable: 'pg_basebackup',
      arguments: ['--version'],
      timeout: const Duration(seconds: 5),
    );

    return result.fold(
      (processResult) {
        if (processResult.isSuccess) {
          LoggerService.info('pg_basebackup encontrado e disponível');
          return const rd.Success(true);
        } else {
          LoggerService.warning(
            'pg_basebackup não encontrado (exit code: ${processResult.exitCode})',
          );
          return const rd.Failure(
            ValidationFailure(
              message:
                  'pg_basebackup não está disponível no PATH do sistema.\n\n'
                  'Para fazer backup de PostgreSQL, você precisa:\n'
                  '1. Instalar PostgreSQL (inclui pg_basebackup)\n'
                  '2. Adicionar o caminho bin ao PATH do Windows\n'
                  '   (ex: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
                  r'Consulte: docs\path_setup.md',
            ),
          );
        }
      },
      (failure) {
        final errorMessage = failure is Failure
            ? failure.message
            : failure.toString();
        LoggerService.warning('Erro ao verificar pg_basebackup: $errorMessage');
        return const rd.Failure(
          ValidationFailure(
            message:
                'pg_basebackup não está disponível no PATH do sistema.\n\n'
                'Para fazer backup de PostgreSQL, você precisa:\n'
                '1. Instalar PostgreSQL (inclui pg_basebackup)\n'
                '2. Adicionar o caminho bin ao PATH do Windows\n'
                '   (ex: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
                r'Consulte: docs\path_setup.md',
          ),
        );
      },
    );
  }

  Future<rd.Result<bool>> verifyPgVerifybackup() async {
    LoggerService.info('Verificando se pg_verifybackup está disponível...');

    final result = await _processService.run(
      executable: 'pg_verifybackup',
      arguments: ['--version'],
      timeout: const Duration(seconds: 5),
    );

    return result.fold(
      (processResult) {
        if (processResult.isSuccess) {
          LoggerService.info('pg_verifybackup encontrado e disponível');
          return const rd.Success(true);
        } else {
          LoggerService.warning(
            'pg_verifybackup não encontrado (exit code: ${processResult.exitCode})',
          );
          return const rd.Failure(
            ValidationFailure(
              message:
                  'pg_verifybackup não está disponível no PATH do sistema.\n\n'
                  'Para verificar backups PostgreSQL, você precisa:\n'
                  '1. Instalar PostgreSQL (inclui pg_verifybackup)\n'
                  '2. Adicionar o caminho bin ao PATH do Windows\n'
                  '   (ex: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
                  r'Consulte: docs\path_setup.md',
            ),
          );
        }
      },
      (failure) {
        final errorMessage = failure is Failure
            ? failure.message
            : failure.toString();
        LoggerService.warning(
          'Erro ao verificar pg_verifybackup: $errorMessage',
        );
        return const rd.Failure(
          ValidationFailure(
            message:
                'pg_verifybackup não está disponível no PATH do sistema.\n\n'
                'Para verificar backups PostgreSQL, você precisa:\n'
                '1. Instalar PostgreSQL (inclui pg_verifybackup)\n'
                '2. Adicionar o caminho bin ao PATH do Windows\n'
                '   (ex: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
                r'Consulte: docs\path_setup.md',
          ),
        );
      },
    );
  }

  /// Regex que casa com a tagline de versao do Firebird CLI
  /// (`WI-V3.0.10.33601 Firebird 3.0`, `WI-V4.0.5.3144`, etc.).
  /// Usar este token e mais robusto que apenas confiar no exit code:
  /// ajuda a distinguir o `isql` real do Firebird do `isql` do
  /// unixODBC (colisao de nome), e captura mensagens de versao mesmo
  /// quando a CLI usa exit code != 0 (algumas builds antigas).
  static final RegExp _firebirdVersionToken = RegExp(
    r'\bWI-V[\d.]+',
    caseSensitive: false,
  );

  Future<rd.Result<bool>> verifyFirebirdCliTools() async {
    try {
      LoggerService.info(
        'Verificando ferramentas Firebird (gbak, nbackup, gstat, isql)...',
      );

      for (final tool in const ['gbak', 'nbackup', 'gstat', 'isql']) {
        final result = await _processService.run(
          executable: tool,
          arguments: const ['-z'],
          timeout: const Duration(seconds: 5),
        );

        final outcome = result.fold<rd.Result<bool>>(
          (pr) {
            // `-z` imprime a tagline `WI-V<major.minor.patch...>` em
            // stdout (ou stderr em algumas versoes). Se o token nao
            // aparecer, e provavel que estejamos perante outro binario
            // homonimo (ex.: isql do unixODBC) ou versao Firebird
            // muito antiga sem suporte a `-z` — ambos cenarios em que
            // a CLI nao serve para o backup.
            final combined = '${pr.stdout}\n${pr.stderr}';
            final matched = _firebirdVersionToken.hasMatch(combined);
            if (pr.isSuccess && matched) {
              LoggerService.info(
                '$tool encontrado e disponivel (Firebird CLI '
                'reconhecida via WI-V tagline)',
              );
              return const rd.Success(true);
            }
            if (!pr.isSuccess) {
              LoggerService.warning(
                '$tool indisponivel ou falhou ao executar -z '
                '(exit: ${pr.exitCode})',
              );
            } else {
              LoggerService.warning(
                '$tool respondeu a -z mas nao tem tagline Firebird '
                '(WI-V*); pode ser binario homonimo nao-Firebird.',
              );
            }
            return rd.Failure(
              ValidationFailure(
                message: ToolPathHelp.buildMessage(tool),
              ),
            );
          },
          (Object failure) {
            final errorMessage = failure is Failure
                ? failure.message
                : failure.toString();
            LoggerService.warning('Erro ao verificar $tool: $errorMessage');
            return rd.Failure(
              ValidationFailure(
                message: ToolPathHelp.buildMessage(tool),
              ),
            );
          },
        );
        if (outcome.isError()) {
          return outcome;
        }
      }

      return const rd.Success(true);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao verificar ferramentas Firebird',
        e,
        stackTrace,
      );
      return rd.Failure(
        ValidationFailure(
          message: 'Erro ao verificar ferramentas Firebird: $e',
        ),
      );
    }
  }
}
