import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';

/// Helper para mensagens de erro de integridade pós-upload, comum aos
/// destination services remotos (Dropbox, Google Drive, Nextcloud).
///
/// **Por que existe**: os três serviços tinham, no respectivo
/// `get<Service>ErrorMessage`, o mesmo prólogo:
///
/// ```dart
/// if (e is Failure && e.code != null) {
///   if (e.code == FailureCodes.integrityValidationInconclusive) {
///     return 'Não foi possível confirmar a integridade no <Service>.\n'
///         'Detalhes: ${e.message}';
///   }
///   if (e.code == FailureCodes.integrityValidationFailed) {
///     return 'Falha de integridade no <Service>: arquivo remoto não confere '
///         'com o original.\n'
///         'Detalhes: ${e.message}';
///   }
/// }
/// ```
///
/// O resto de cada `get*ErrorMessage` é específico de cada API (códigos
/// HTTP do provedor, `DioException`, `drive.DetailedApiRequestError`,
/// `HandshakeException` do Nextcloud, etc.) — só este prólogo é trivial
/// e idêntico. Centralizar aqui evita drift de tradução e garante uma
/// única origem de verdade para o copy mostrado ao usuário em falhas
/// de validação de integridade.
class IntegrityFailureMessages {
  IntegrityFailureMessages._();

  /// Retorna a mensagem amigável correspondente a um failure de
  /// integridade (`integrityValidation*`), ou `null` quando [error]
  /// não é um failure de integridade — sinalizando ao chamador que
  /// deve seguir para a próxima camada de mapeamento (tipo da
  /// exceção, status HTTP, heurística por substring).
  ///
  /// [serviceName] aparece literalmente no texto (ex.: `"Dropbox"`,
  /// `"Google Drive"`, `"Nextcloud"`).
  static String? tryDescribe(Object? error, {required String serviceName}) {
    if (error is! Failure || error.code == null) return null;
    if (error.code == FailureCodes.integrityValidationInconclusive) {
      return 'Não foi possível confirmar a integridade no $serviceName.\n'
          'Detalhes: ${error.message}';
    }
    if (error.code == FailureCodes.integrityValidationFailed) {
      return 'Falha de integridade no $serviceName: arquivo remoto não confere '
          'com o original.\n'
          'Detalhes: ${error.message}';
    }
    return null;
  }
}
