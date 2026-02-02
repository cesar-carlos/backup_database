enum ErrorCode {
  unknown('UNKNOWN', 'Erro desconhecido'),
  invalidRequest('INVALID_REQUEST', 'Requisição inválida'),
  pathNotAllowed('PATH_NOT_ALLOWED', 'Caminho não permitido'),
  fileNotFound('FILE_NOT_FOUND', 'Arquivo não encontrado'),
  directoryNotFound('DIRECTORY_NOT_FOUND', 'Diretório não encontrado'),
  permissionDenied('PERMISSION_DENIED', 'Permissão negada'),
  parseError('PARSE_ERROR', 'Erro ao processar mensagem'),
  authenticationFailed('AUTH_FAILED', 'Autenticação falhou'),
  connectionLost('CONNECTION_LOST', 'Conexão perdida'),
  timeout('TIMEOUT', 'Operação expirou'),
  ioError('IO_ERROR', 'Erro de entrada/saída'),
  diskFull('DISK_FULL', 'Disco cheio'),
  invalidChecksum('INVALID_CHECKSUM', 'Checksum inválido');

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
