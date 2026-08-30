import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class SybaseCliRunner {
  SybaseCliRunner({
    required this._processService,
    this._useCredentialsFile = true,
  });

  final ps.ProcessService _processService;
  final bool _useCredentialsFile;

  /// Prefixo dos diretórios temporários criados em
  /// [runWithCredentials]. Específico o suficiente para não
  /// colidir com dirs criados por testes (que tipicamente usam prefixos
  /// como `sybase_backup_test_`) ou outros consumidores de
  /// `Directory.systemTemp`.
  static const String credentialsTempDirPrefix = 'sybase_backup_creds_';

  /// Remove diretórios `sybase_backup_creds_*` órfãos em `systemTemp`.
  ///
  /// Quando o processo Dart é morto (Task Manager, BSOD, watchdog) antes
  /// do `finally` do [runWithCredentials] rodar, o diretório
  /// temporário (com o `args.txt` contendo `PWD=...` em texto puro) fica
  /// no disco indefinidamente. Este método varre `systemTemp` no boot do
  /// service e remove diretórios com o prefixo conhecido.
  Future<void> cleanupOrphanCredentialDirs() async {
    try {
      final tempDir = Directory.systemTemp;
      if (!await tempDir.exists()) return;
      await for (final entity in tempDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith(credentialsTempDirPrefix)) continue;
        try {
          await entity.delete(recursive: true);
          LoggerService.debug(
            'Removido diretório órfão de credenciais Sybase: ${entity.path}',
          );
        } on Object catch (e) {
          // Outro processo (talvez outro backup em execução) pode estar
          // segurando o diretório. Skip silencioso — pegaremos no próximo
          // boot.
          LoggerService.debug(
            'Não foi possível remover ${entity.path} (em uso?): $e',
          );
        }
      }
    } on Object catch (e, stackTrace) {
      LoggerService.debug(
        'Cleanup de diretórios órfãos Sybase falhou: $e',
        e,
        stackTrace,
      );
    }
  }

  /// Executa um utilitário Sybase (dbisql/dbbackup) escrevendo a lista de
  /// argumentos em um arquivo temporário e invocando `<exe> @<arquivo>`.
  ///
  /// Vantagens em relação a passar a senha como argumento direto:
  ///  - A connection string (com `PWD=...`) não aparece em ferramentas
  ///    como `tasklist /v`/`wmic process` (Windows) ou `ps -ef` (Linux).
  ///  - O arquivo é criado no diretório temporário do usuário e removido
  ///    no `finally`, mesmo em caso de falha/timeout.
  ///
  /// Se a escrita do arquivo falhar (caso muito raro), faz fallback para a
  /// execução direta com aviso em log para preservar a operação do backup.
  Future<rd.Result<ps.ProcessResult>> runWithCredentials({
    required String executable,
    required List<String> arguments,
    required Duration timeout,
    String? tag,
  }) async {
    if (!_useCredentialsFile) {
      // Modo de testes/legacy: executa diretamente preservando o array
      // de argumentos para que mocks possam inspecionar a chamada.
      return _processService.run(
        executable: executable,
        arguments: arguments,
        timeout: timeout,
        tag: tag,
      );
    }
    File? credentialsFile;
    try {
      final tempDir = await Directory.systemTemp.createTemp(
        credentialsTempDirPrefix,
      );
      credentialsFile = File(p.join(tempDir.path, 'args.txt'));
      // Cada argumento em uma linha; valores com espaços já vêm sem aspas
      // (a Sybase Tools faz parsing de uma linha por argumento neste modo).
      final buffer = StringBuffer();
      arguments.forEach(buffer.writeln);
      await credentialsFile.writeAsString(buffer.toString(), flush: true);

      final result = await _processService.run(
        executable: executable,
        arguments: ['@${credentialsFile.path}'],
        timeout: timeout,
        tag: tag,
      );
      return result;
    } on Object catch (e, stackTrace) {
      // M1: degradação de segurança — quando o arquivo de credenciais
      // falha, a senha acaba indo no `arguments` do processo filho
      // (visível em `tasklist /v` no Windows). Logamos como ERRO para
      // garantir visibilidade no painel de logs do app, não warning.
      LoggerService.error(
        'Falha ao usar arquivo de credenciais para $executable; '
        'fazendo fallback para execução direta — a senha pode ficar '
        'visível em `tasklist /v`/`ps -ef` durante a execução. Erro: $e',
        e,
        stackTrace,
      );
      return _processService.run(
        executable: executable,
        arguments: arguments,
        timeout: timeout,
        tag: tag,
      );
    } finally {
      if (credentialsFile != null) {
        try {
          if (await credentialsFile.exists()) {
            await credentialsFile.delete();
          }
          final parent = credentialsFile.parent;
          if (await parent.exists()) {
            await parent.delete(recursive: true);
          }
        } on Object catch (e) {
          LoggerService.debug(
            'Não foi possível remover arquivo temporário de credenciais: $e',
          );
        }
      }
    }
  }
}
