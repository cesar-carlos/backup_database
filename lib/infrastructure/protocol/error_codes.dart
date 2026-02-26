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
  invalidChecksum('INVALID_CHECKSUM', 'Checksum invalido')
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
