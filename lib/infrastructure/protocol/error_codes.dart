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
  payloadTooLarge('PAYLOAD_TOO_LARGE', 'Payload excede o limite permitido')
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
