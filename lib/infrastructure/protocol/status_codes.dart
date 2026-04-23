import 'package:backup_database/infrastructure/protocol/error_codes.dart';

/// Tabela oficial de `statusCode` da API remota (REST-like sobre socket).
///
/// Implementa a parte tabular de F0.5 + F0.6 do plano + parte de
/// P0.1 (envelope `v1`). Codigos seguem semantica HTTP por familia:
///
/// - **2xx**: sucesso. `200` sincrono concluido, `202` aceito para
///   processamento assincrono.
/// - **4xx**: erro do cliente (request invalida, conflito de estado).
/// - **5xx**: erro do servidor (interno ou pre-requisito nao atendido).
///
/// O servidor inclui `statusCode` no payload de toda resposta de erro
/// via `createErrorMessage` (entrega 2026-04-19). Outros handlers
/// migram gradualmente para incluir tambem em respostas de sucesso —
/// cliente le quando presente e ignora quando ausente (backward-compat
/// com servidor `v1`).
class StatusCodes {
  StatusCodes._();

  /// Sucesso sincrono — operacao concluida e o `data` esta presente.
  static const int ok = 200;

  /// Aceito para processamento assincrono — execucao iniciada ou
  /// enfileirada. `data` pode incluir `runId`/`queuedPosition`.
  static const int accepted = 202;

  /// Requisicao invalida — payload malformado, campo obrigatorio
  /// ausente, valor fora de dominio.
  static const int badRequest = 400;

  /// Nao autenticado — handshake nao concluido ou sessao expirada.
  static const int unauthorized = 401;

  /// Sem permissao — autenticado mas operacao nao permitida pela
  /// licenca ou role.
  static const int forbidden = 403;

  /// Recurso nao encontrado — `runId`/`scheduleId`/arquivo inexistente.
  static const int notFound = 404;

  /// Conflito de estado — operacao incompativel com estado atual
  /// (backup ja em execucao, transicao invalida, schedule duplicado
  /// na fila).
  static const int conflict = 409;

  /// Recurso expirado/indisponivel — artefato removido por TTL,
  /// item de fila vencido, sessao terminada.
  static const int gone = 410;

  /// Validacao de dominio falhou — payload sintaticamente correto
  /// mas semanticamente invalido (ex.: data passada no agendamento).
  static const int unprocessableEntity = 422;

  /// Limite excedido — fila cheia, rate limit por cliente, throughput.
  static const int tooManyRequests = 429;

  /// Erro interno do servidor — excecao nao tratada, bug.
  static const int internalServerError = 500;

  /// Servico indisponivel ou pre-requisito nao atendido — staging
  /// cheio, ferramenta de compactacao ausente, banco inacessivel.
  static const int serviceUnavailable = 503;

  /// Mapeamento `ErrorCode -> statusCode` segundo a politica oficial
  /// do plano. Codigos sem entrada explicita caem em [internalServerError]
  /// — fail-safe que torna obvia a falta de mapping para revisao.
  static const Map<ErrorCode, int> _byErrorCode = <ErrorCode, int>{
    // Validacao / requisicao
    ErrorCode.invalidRequest: badRequest,
    ErrorCode.parseError: badRequest,
    ErrorCode.payloadTooLarge: badRequest,
    ErrorCode.invalidChecksum: badRequest,

    // Auth / autorizacao
    ErrorCode.authenticationFailed: unauthorized,
    ErrorCode.notAuthenticated: unauthorized,
    ErrorCode.licenseDenied: forbidden,
    ErrorCode.permissionDenied: forbidden,
    ErrorCode.pathNotAllowed: forbidden,

    // Nao encontrado
    ErrorCode.fileNotFound: notFound,
    ErrorCode.directoryNotFound: notFound,
    ErrorCode.scheduleNotFound: notFound,

    // Recurso expirou (retencao/TTL)
    ErrorCode.artifactExpired: gone,

    // Conflito de estado
    ErrorCode.fileBusy: conflict,
    ErrorCode.backupAlreadyRunning: conflict,
    ErrorCode.noActiveExecution: conflict,

    // Servico / pre-requisito
    ErrorCode.unsupportedProtocolVersion: serviceUnavailable,
    ErrorCode.diskFull: serviceUnavailable,
    ErrorCode.stagingFull: serviceUnavailable,
    ErrorCode.ioError: serviceUnavailable,

    // Conexao
    ErrorCode.connectionLost: serviceUnavailable,
    ErrorCode.timeout: serviceUnavailable,

    // Generico
    ErrorCode.unknown: internalServerError,
  };

  /// Retorna o `statusCode` oficial para o [ErrorCode] informado.
  /// Codigos novos sem entrada explicita caem em [internalServerError]
  /// para tornar obvia a falta de mapping em testes/code review.
  static int forErrorCode(ErrorCode code) =>
      _byErrorCode[code] ?? internalServerError;

  /// Mapa publico imutavel para inspecao/teste/golden.
  static Map<ErrorCode, int> get all => Map.unmodifiable(_byErrorCode);

  /// `true` quando [statusCode] denota sucesso (200-299).
  static bool isSuccess(int statusCode) =>
      statusCode >= 200 && statusCode < 300;

  /// `true` quando [statusCode] denota erro do cliente (400-499).
  static bool isClientError(int statusCode) =>
      statusCode >= 400 && statusCode < 500;

  /// `true` quando [statusCode] denota erro do servidor (500-599).
  static bool isServerError(int statusCode) =>
      statusCode >= 500 && statusCode < 600;

  /// `true` quando o erro e tipicamente retryable pelo cliente (5xx
  /// + 408 timeout + 429 rate limit). Cliente deve aplicar backoff
  /// exponencial nesses casos.
  static bool isRetryable(int statusCode) =>
      statusCode == tooManyRequests || isServerError(statusCode);
}
