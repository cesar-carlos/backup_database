import 'package:backup_database/core/errors/failure.dart';

String mapExceptionToMessage(Object? exception) {
  if (exception == null) {
    return 'Ocorreu um erro desconhecido. Tente novamente.';
  }

  final message = exception.toString();

  // Check if it's a domain Failure with specific type information
  if (exception is Failure) {
    // Network failures
    if (exception is NetworkFailure) {
      return 'Erro de rede ao comunicar com o servidor. '
          'Verifique sua conexão e tente novamente.';
    }

    // Server failures with specific codes
    if (exception is ServerFailure) {
      switch (exception.code) {
        case 'CONNECTION_REFUSED':
          return 'Servidor não respondeu. Verifique se o servidor está online.';
        case 'TIMEOUT':
          return 'Tempo esgotado ao aguardar resposta do servidor.';
        case 'UNAUTHORIZED':
          return 'Senha incorreta ou acesso negado pelo servidor.';
        case 'NOT_FOUND':
          return 'Agendamento não encontrado no servidor.';
        default:
          return 'Erro no servidor: ${exception.message}';
      }
    }

    // Other failure types
    if (exception is ValidationFailure) {
      return 'Dados inválidos: ${exception.message}';
    }

    if (exception is FileSystemFailure) {
      return 'Erro no sistema de arquivos: ${exception.message}';
    }

    return exception.message.isNotEmpty
        ? exception.message
        : 'Ocorreu um erro desconhecido. Tente novamente.';
  }

  // Handle generic exceptions
  if (message.contains('ConnectionManager not connected')) {
    return 'Conecte-se a um servidor para realizar esta operação.';
  }

  if (message.contains('Disconnected') ||
      message.contains('disconnected') ||
      message.contains('Conexão perdida')) {
    if (message.contains('during file transfer')) {
      return 'Conexão perdida durante o download. Reconecte-se e tente novamente.';
    }
    if (message.contains('during backup')) {
      return 'Conexão perdida durante o backup. O backup pode ter continuado no servidor.';
    }
    return 'Você foi desconectado do servidor. Reconecte-se para continuar.';
  }

  if ((message.contains('conclusão do backup') ||
          message.contains('conclusao do backup')) &&
      message.contains('limite')) {
    final limitMatch = RegExp(r'limite:\s*(\d+)').firstMatch(message);
    final minutes = limitMatch != null ? limitMatch.group(1) : '10';
    return 'O backup passou do tempo limite ($minutes min). '
        'Verifique no servidor se foi concluído.';
  }

  if (message.contains('timeout') || message.contains('TimeoutException')) {
    return 'Tempo esgotado ao aguardar resposta do servidor.';
  }

  if (message.contains('Resposta inesperada')) {
    return 'Resposta inesperada do servidor. Tente novamente.';
  }

  if (message.contains('Erro desconhecido')) {
    return 'Erro no servidor: $message';
  }

  return message.isNotEmpty
      ? message
      : 'Ocorreu um erro desconhecido. Tente novamente.';
}
