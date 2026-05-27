import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:path/path.dart' as p;

/// Helpers compartilhados para validar instalacoes embedded do Firebird
/// (Windows + FB 3+) e para montar o `Path`/`PATH` para o `fbclient.dll`
/// configurado.
///
/// Extraido do `FirebirdBackupService` para que outros consumidores (ex.:
/// `SqlScriptExecutionService` para scripts pos-backup com `isql`) usem
/// exatamente a mesma validacao em vez de duplicar a logica.
class FirebirdEmbeddedSupport {
  FirebirdEmbeddedSupport._();

  static const String engine12Dll = 'engine12.dll';
  static const String engine13Dll = 'engine13.dll';

  /// Em Windows + FB 3.0+ embedded, exige que o `clientLibraryPath`
  /// aponte para um `fbclient.dll` real e que exista o plugin
  /// `engine12.dll` (hint 3.0) ou `engine13.dll` (hint 4.0) — ou
  /// qualquer um dos dois para hint `auto`.
  ///
  /// Aceita as duas convencoes de instalacao habituais:
  /// - **Instalador oficial:** `<root>/bin/fbclient.dll` +
  ///   `<root>/plugins/engine1?.dll`.
  /// - **Zip embedded:** `<root>/fbclient.dll` +
  ///   `<root>/plugins/engine1?.dll`.
  ///
  /// Retorna `null` quando OK (ou quando nao se aplica a este
  /// SO/hint). Retorna `ValidationFailure` com mensagem accionavel
  /// quando falta algum plugin.
  static Future<ValidationFailure?> validateEmbeddedEnginePlugins(
    FirebirdConfig config,
  ) async {
    if (!config.useEmbedded || !Platform.isWindows) {
      return null;
    }
    if (config.serverVersionHint == FirebirdServerVersionHint.v25) {
      return null;
    }

    final clientRaw = config.clientLibraryPath?.trim();
    if (clientRaw == null || clientRaw.isEmpty) {
      return const ValidationFailure(
        message:
            'Modo embedded Firebird 3.0+ no Windows requer Client library path '
            '(fbclient.dll) para validar a pasta plugins (engine12.dll / '
            'engine13.dll).',
      );
    }

    final clientAbs = p.normalize(File(clientRaw).absolute.path);
    if (!await File(clientAbs).exists()) {
      return ValidationFailure(
        message: 'Client library Firebird nao encontrado: $clientAbs',
      );
    }

    final binDir = p.dirname(clientAbs);
    final candidateRoots = <String>{
      p.normalize(p.join(binDir, '..')),
      binDir,
    };
    final candidatePluginsDirs = candidateRoots
        .map((root) => p.join(root, 'plugins'))
        .toList(growable: false);

    Future<bool> hasPluginAnywhere(String fileName) async {
      for (final dir in candidatePluginsDirs) {
        if (await File(p.join(dir, fileName)).exists()) {
          return true;
        }
      }
      return false;
    }

    String pluginsDirSearchList() =>
        candidatePluginsDirs.map((d) => "'$d'").join(' ou ');

    final hint = config.serverVersionHint;
    if (hint == FirebirdServerVersionHint.v40) {
      if (!await hasPluginAnywhere(engine13Dll)) {
        return ValidationFailure(
          message:
              'Firebird embedded 4.0: nao encontrado $engine13Dll em '
              '${pluginsDirSearchList()}. Use uma instalacao completa '
              'do servidor ou copie os plugins para essa pasta.',
        );
      }
      return null;
    }
    if (hint == FirebirdServerVersionHint.v30) {
      if (!await hasPluginAnywhere(engine12Dll)) {
        return ValidationFailure(
          message:
              'Firebird embedded 3.0: nao encontrado $engine12Dll em '
              '${pluginsDirSearchList()}. Use uma instalacao completa '
              'do servidor ou copie os plugins para essa pasta.',
        );
      }
      return null;
    }
    if (hint == FirebirdServerVersionHint.auto) {
      final has12 = await hasPluginAnywhere(engine12Dll);
      final has13 = await hasPluginAnywhere(engine13Dll);
      if (!has12 && !has13) {
        return ValidationFailure(
          message:
              'Firebird embedded (hint Auto): nao encontrado $engine12Dll '
              'nem $engine13Dll em '
              '${pluginsDirSearchList()}. Confira a instalacao ou defina '
              'o hint de versao (3.0 / 4.0).',
        );
      }
    }

    return null;
  }

  /// Retorna o env map que injecta o diretorio do `fbclient.dll` no
  /// `Path` (Windows) / `PATH` (POSIX) para que processos filhos
  /// resolvam o cliente Firebird correto. Devolve `null` quando o
  /// utilizador nao definiu `clientLibraryPath`.
  static Map<String, String>? clientLibEnvironment(FirebirdConfig config) {
    final lib = config.clientLibraryPath?.trim();
    if (lib == null || lib.isEmpty) {
      return null;
    }
    final dir = p.dirname(lib);
    final key = Platform.isWindows ? 'Path' : 'PATH';
    final current = Platform.environment[key] ?? Platform.environment['PATH'];
    if (current == null || current.isEmpty) {
      return {key: dir};
    }
    final sep = Platform.isWindows ? ';' : ':';
    return {key: '$dir$sep$current'};
  }
}
