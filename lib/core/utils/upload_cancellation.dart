import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Sentinel exception lançada pelos destination services quando o
/// upload em andamento detecta um sinal de cancelamento (via callback
/// `bool Function()? isCancelled`).
///
/// **Por que pública** (e por que `const`):
/// - Antes desta consolidação, cada destination service
///   (Dropbox/Drive/Nextcloud/FTP) declarava sua **própria** classe
///   `_UploadCancelledException` privada, idêntica módulo a módulo.
///   Isso impedia que helpers compartilhados (por ex. um wrapper de
///   `Stream.map` que emite `addError(...)`) propagassem a sentinel
///   cross-service e exigia duplicar o `_throwIfCancelled` 4×.
/// - A classe é trivial e imutável, então expor publicamente não
///   acrescenta superfície de API significativa — quem importa o
///   símbolo está obrigatoriamente em código de upload.
/// - `const` permite reutilizar a mesma instância em todos os pontos
///   de lançamento (incluindo dentro de `addError(...)` em streams
///   single-subscription), eliminando alocações por chunk.
class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() =>
      'UploadCancelledException: upload cancelado pelo usuário';
}

/// Coletânea de helpers compartilhados para o tratamento de
/// cancelamento de uploads pelos destination services (e pelo
/// orchestrator de envio).
///
/// Substitui a duplicação histórica em que cada destination service
/// (Dropbox/Drive/Nextcloud/FTP) e o `DestinationOrchestratorImpl`
/// repetiam:
/// - `class _UploadCancelledException implements Exception {}`
/// - `void _throwIfCancelled(bool Function()? isCancelled) { ... }`
/// - `BackupFailure(message: 'Upload cancelado pelo usuário.', code:
///   FailureCodes.uploadCancelled)`
///
/// Centralizar aqui garante:
/// 1. Uma única mensagem ao usuário final (sem drift de tradução).
/// 2. Uma única forma de detectar e propagar o cancelamento
///    (`is UploadCancelledException`).
/// 3. Failure const-reutilizável (sem alocação por destino/retry).
class UploadCancellation {
  UploadCancellation._();

  /// Failure canônica para "upload cancelado pelo usuário".
  ///
  /// Use este `const` em vez de construir um `BackupFailure` ad-hoc
  /// (mensagem + `FailureCodes.uploadCancelled`). É seguro retornar
  /// diretamente: `return UploadCancellation.cancelledFailure;` —
  /// `rd.Failure(...)` em torno de uma const também é const, mas como
  /// `rd.Failure` não é exposto como `const` em `result_dart`, expomos
  /// o `BackupFailure` puro e cada chamador embrulha com
  /// `rd.Failure(UploadCancellation.cancelledFailure)`.
  static const BackupFailure cancelledFailure = BackupFailure(
    message: 'Upload cancelado pelo usuário.',
    code: FailureCodes.uploadCancelled,
  );

  /// Result pronto-para-retornar com o cancelamento canônico.
  ///
  /// Atalho para `rd.Failure(UploadCancellation.cancelledFailure)` —
  /// retornado dos serviços via `return UploadCancellation.cancelledResult();`.
  static rd.Result<T> cancelledResult<T extends Object>() =>
      const rd.Failure(cancelledFailure);

  /// Lança [UploadCancelledException] **se** o callback opcional
  /// `isCancelled` foi fornecido **e** já sinalizou cancelamento.
  ///
  /// Esta era a função privada `_throwIfCancelled` duplicada em 4
  /// destination services — todos com a mesma assinatura e o mesmo
  /// corpo. Centralizada aqui como `static`.
  static void throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) {
      throw const UploadCancelledException();
    }
  }

  /// `true` se [error] representa um cancelamento de upload — tanto
  /// diretamente quanto embrulhado em `DioException.error` (caso em
  /// que o `addError(UploadCancelledException())` num stream é
  /// re-propagado pelo Dio como `DioExceptionType.unknown`).
  ///
  /// Usado pelo Nextcloud (que embrulha via `sink.addError(...)`).
  /// Mantemos a verificação genérica de `error.toString().contains(...)`
  /// fora deste helper porque é específica de cada serviço (FTP
  /// inspeciona mensagens em inglês, Dropbox em HTTP, etc.).
  static bool isCancellation(Object? error) {
    if (error is UploadCancelledException) return true;
    // Importar `dio` aqui acoplaria o `core` ao `package:dio`. Em vez
    // disso, comparamos via `dynamic` access a `.error` quando existe
    // — o método `runtimeType.toString()` evita falsos positivos
    // sem precisar importar o tipo `DioException`.
    if (error == null) return false;
    try {
      final inner = (error as dynamic).error;
      return inner is UploadCancelledException;
    } on Object {
      return false;
    }
  }
}
