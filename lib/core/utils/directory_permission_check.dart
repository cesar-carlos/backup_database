import 'dart:io';
import 'dart:math';

import 'package:backup_database/core/utils/logger_service.dart';

/// Verifica permissão de escrita em diretórios via "probe file" (cria,
/// verifica existência e remove). Centraliza o pattern que aparecia
/// duplicado em pelo menos 3 lugares (`SchedulerService`,
/// `ValidateBackupDirectory` use case, `ScheduleDialog`).
///
/// Por que probe file em vez de `stat`?
/// - `stat` no Windows não reflete permissões de write reais
///   confiavelmente (UAC, ACLs herdadas, redirects de pasta protegida).
/// - O write de `.backup_permission_test_<ts>_<rand>` é a única forma
///   robusta de garantir que o caller realmente conseguirá criar o
///   backup ali.
class DirectoryPermissionCheck {
  DirectoryPermissionCheck._();

  /// Probe usado para evitar colisão com arquivos legítimos do usuário.
  /// O timestamp + random suffix tornam improvável colisão entre
  /// chamadas simultâneas no mesmo diretório.
  static const String _probePrefix = '.backup_permission_test_';

  static final Random _random = Random();

  /// Cria um arquivo de teste, valida que existe, e remove. Retorna `true`
  /// se a sequência funciona; `false` em qualquer falha (com warning log).
  ///
  /// O método é defensivo: nunca propaga exceções — apenas loga e
  /// retorna `false`. Callers usam o boolean para decidir mensagem de
  /// erro ao usuário.
  static Future<bool> hasWritePermission(Directory directory) async {
    try {
      // Bug histórico: usar apenas `millisecondsSinceEpoch` causava
      // colisão quando duas chamadas concorrentes pegavam o mesmo
      // timestamp (sub-millisecond) — uma terminava deletando o probe
      // file da outra, e o segundo `exists()` falhava. O sufixo
      // aleatório elimina o race.
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomSuffix = _random.nextInt(1 << 32).toRadixString(16);
      final testFileName = '$_probePrefix${timestamp}_$randomSuffix';
      final testFile = File(
        '${directory.path}${Platform.pathSeparator}$testFileName',
      );

      await testFile.writeAsString('test');

      if (await testFile.exists()) {
        await testFile.delete();
        return true;
      }

      return false;
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao verificar permissão de escrita na pasta '
        '${directory.path}: $e',
      );
      return false;
    }
  }

  /// Variante que recebe um path string para callers que ainda não
  /// instanciaram um `Directory`. Equivalente a
  /// `hasWritePermission(Directory(path))`.
  static Future<bool> hasWritePermissionForPath(String path) =>
      hasWritePermission(Directory(path));
}
