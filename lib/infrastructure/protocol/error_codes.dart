enum ErrorCode {
  unknown('UNKNOWN', 'Erro desconhecido'),
  invalidRequest('INVALID_REQUEST', 'Requisicao invalida'),
  pathNotAllowed('PATH_NOT_ALLOWED', 'Caminho não permitido'),
  fileNotFound('FILE_NOT_FOUND', 'Arquivo não encontrado'),
  fileBusy('FILE_BUSY', 'Arquivo em uso por outro cliente'),
  directoryNotFound('DIRECTORY_NOT_FOUND', 'Diretório não encontrado'),
  permissionDenied('PERMISSION_DENIED', 'Permissao negada'),
  licenseDenied('LICENSE_DENIED', 'Licença não permite esta operação'),
  parseError('PARSE_ERROR', 'Erro ao processar mensagem'),
  authenticationFailed('AUTH_FAILED', 'Autenticação falhou'),
  connectionLost('CONNECTION_LOST', 'Conexão perdida'),
  timeout('TIMEOUT', 'Operacao expirou'),
  ioError('IO_ERROR', 'Erro de entrada/saida'),
  diskFull('DISK_FULL', 'Disco cheio'),

  /// Staging de transferencia remota acima do limite (PR-4 / M5.3).
  /// Mapeia para 503.
  stagingFull(
    'STAGING_FULL',
    'Staging remoto acima do limite configurado',
  ),
  invalidChecksum('INVALID_CHECKSUM', 'Checksum invalido'),

  /// Wire version do `MessageHeader` nao reconhecida pelo servidor.
  /// Indica peer com protocolo binario incompativel (ver ADR-003).
  /// Cliente deve atualizar para versao compativel.
  unsupportedProtocolVersion(
    'UNSUPPORTED_PROTOCOL_VERSION',
    'Versao do protocolo binario nao suportada',
  ),

  /// Payload da mensagem excede o limite permitido para o seu
  /// `MessageType` (ver `PayloadLimits.maxPayloadBytesFor`). Defesa em
  /// profundidade contra peer hostil ou bug de cliente que envia
  /// payload muito maior que o uso esperado (M5.4 do plano).
  payloadTooLarge('PAYLOAD_TOO_LARGE', 'Payload excede o limite permitido'),

  /// Cliente tentou disparar backup remoto enquanto outro ja esta em
  /// execucao no servidor. Mapeia para 409 (conflito de estado).
  /// Cliente deve aguardar `backupComplete`/`backupFailed` ou consultar
  /// `getExecutionStatus(runId)` antes de tentar novamente. Codigo
  /// padronizado conforme F0.2/F2.11 do plano.
  backupAlreadyRunning(
    'BACKUP_ALREADY_RUNNING',
    'Ja existe um backup em execucao no servidor',
  ),

  /// `scheduleId` referenciado nao existe (foi removido ou nunca
  /// existiu). Mapeia para 404. Diferente de `fileNotFound` para nao
  /// confundir cliente entre arquivo de staging e schedule de dominio.
  scheduleNotFound('SCHEDULE_NOT_FOUND', 'Agendamento nao encontrado'),

  /// Cliente tentou cancelar/consultar execucao que nao esta ativa
  /// no momento (registry sem entrada para o `scheduleId`/`runId`).
  /// Mapeia para 409 — conflito de estado, nao 404, porque o recurso
  /// (schedule) existe; apenas nao ha execucao em curso.
  noActiveExecution(
    'NO_ACTIVE_EXECUTION',
    'Nao ha execucao ativa para este agendamento',
  ),

  /// Cliente enviou mensagem operacional (nao-auth) antes de concluir
  /// o handshake de autenticacao. Mapeia para 401. Cliente deve
  /// completar `authRequest` primeiro. Defesa em profundidade contra
  /// peer hostil ou cliente buggy (F0.1 do plano).
  notAuthenticated(
    'NOT_AUTHENTICATED',
    'Mensagem operacional rejeitada antes de autenticacao concluida',
  ),

  /// Artefato em staging remoto fora da janela de retencao. Mapeia para 410.
  artifactExpired(
    'ARTIFACT_EXPIRED',
    'Artefato de backup removido ou fora do periodo de retencao',
  )
  ;

  final String code;
  final String defaultMessage;

  const ErrorCode(this.code, this.defaultMessage);

  static ErrorCode fromString(String code) {
    return values.firstWhere(
      (e) => e.code == code,
      orElse: () => ErrorCode.unknown,
    );
  }
}
