import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centraliza o carregamento do `.env`. Antes desta classe, o `dotenv.load`
/// era chamado em três pontos diferentes (`main.dart`,
/// `AppInitializer._loadEnvironment` e `ServiceModeInitializer.initialize`)
/// com mensagens de log levemente diferentes; manter sincronizado era
/// fácil de quebrar.
///
/// Idempotente: chamadas após o primeiro load são no-op.
class EnvironmentLoader {
  EnvironmentLoader._();

  /// Carrega o arquivo `.env` se ainda não foi carregado. Captura erros
  /// para não interromper o boot — variáveis ausentes serão tratadas como
  /// `null` pelos consumidores.
  static Future<void> loadIfNeeded({String? logPrefix}) async {
    if (dotenv.isInitialized) {
      LoggerService.debug(
        '${logPrefix ?? '[env]'} variaveis ja carregadas (skip)',
      );
      return;
    }

    try {
      await dotenv.load();
      LoggerService.info(
        '${logPrefix ?? '[env]'} variaveis de ambiente carregadas',
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        '${logPrefix ?? '[env]'} nao foi possivel carregar .env: $e',
        e,
        s,
      );
    }
  }
}
