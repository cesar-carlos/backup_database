import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';

/// Mede o uso de disco de um diretorio de staging em bytes.
///
/// Defensivo: erros de I/O (permissao, diretorio inexistente, link
/// quebrado) sao logados em `debug` e retornam `0` em vez de propagar.
/// Isso garante que metricas continuam respondendo mesmo se o staging
/// for movido/removido externamente — o operador deve detectar o
/// problema via metrica ausente/zero, nao via crash do servidor.
///
/// Implementacao parcial de M5.3 (alerta/bloqueio de
/// `stagingUsageBytes`) e M7.1 (telemetria). O valor publicado em
/// `metricsResponse.stagingUsageBytes` permite ao cliente:
///
/// - exibir uso atual no dashboard;
/// - decidir se vale tentar novo backup remoto (se estiver perto do
///   limite, sugerir cleanup antes);
/// - alimentar alertas operacionais no PR-5+.
class StagingUsageMeasurer {
  StagingUsageMeasurer._();

  /// Soma o tamanho de todos os arquivos sob [basePath] recursivamente.
  ///
  /// Retorna `0` quando:
  /// - [basePath] nao existe;
  /// - listagem ou stat falham por permissao/IO;
  /// - [basePath] esta vazio.
  ///
  /// Diretorios e symlinks sao ignorados; apenas regular files contam.
  static Future<int> measure(String basePath) async {
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      return 0;
    }
    var total = 0;
    try {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            total += stat.size;
          } on Object catch (e, st) {
            LoggerService.debug(
              'StagingUsageMeasurer: stat falhou para ${entity.path}: $e',
              e,
              st,
            );
          }
        }
      }
    } on Object catch (e, st) {
      LoggerService.debug(
        'StagingUsageMeasurer: listagem falhou para $basePath: $e',
        e,
        st,
      );
      return total; // retorna parcial em vez de zerar
    }
    return total;
  }
}
