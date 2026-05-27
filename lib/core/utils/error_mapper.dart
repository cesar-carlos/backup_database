import 'package:backup_database/core/errors/failure.dart';

/// Mapeia exceções/failures internas para mensagens user-facing em
/// português. Centralizada para evitar que cada provider/page reinvente
/// o texto exibido em snackbars e diálogos de erro.
///
/// Use `ErrorMessageMapper.mapToUserMessage(exception)` em vez de
/// `failure.toString()` ou `failure.message` direto — o helper já
/// trata casos especiais (conexão perdida, timeout, etc.) e garante
/// um fallback amigável.
abstract final class ErrorMessageMapper {
  static const String _unknownErrorMessage =
      'Ocorreu um erro desconhecido. Tente novamente.';

  /// Regex `static final` para evitar recompilação a cada chamada
  /// (importante porque o mapper é invocado em hot paths de UI).
  static final RegExp _timeLimitMinutesPattern = RegExp(r'limite:\s*(\d+)');

  static String mapToUserMessage(Object? exception) {
    if (exception == null) {
      return _unknownErrorMessage;
    }

    if (exception is Failure) {
      return _mapDomainFailure(exception);
    }

    return _mapGenericException(exception.toString());
  }

  static String _mapDomainFailure(Failure failure) {
    if (failure is NetworkFailure) {
      return 'Erro de rede ao comunicar com o servidor. '
          'Verifique sua conexão e tente novamente.';
    }

    if (failure is ServerFailure) {
      return _mapServerFailure(failure);
    }

    if (failure is ValidationFailure) {
      return 'Dados inválidos: ${failure.message}';
    }

    if (failure is FileSystemFailure) {
      return 'Erro no sistema de arquivos: ${failure.message}';
    }

    return failure.message.isNotEmpty ? failure.message : _unknownErrorMessage;
  }

  static String _mapServerFailure(ServerFailure failure) {
    switch (failure.code) {
      case 'CONNECTION_REFUSED':
        return 'Servidor não respondeu. Verifique se o servidor está online.';
      case 'TIMEOUT':
        return 'Tempo esgotado ao aguardar resposta do servidor.';
      case 'UNAUTHORIZED':
        return 'Senha incorreta ou acesso negado pelo servidor.';
      case 'NOT_FOUND':
        return 'Agendamento não encontrado no servidor.';
      default:
        return 'Erro no servidor: ${failure.message}';
    }
  }

  static String _mapGenericException(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('connectionmanager not connected')) {
      return 'Conecte-se a um servidor para realizar esta operação.';
    }

    if (lower.contains('disconnected') || message.contains('Conexão perdida')) {
      if (lower.contains('during file transfer')) {
        return 'Conexão perdida durante o download. '
            'Reconecte-se e tente novamente.';
      }
      if (lower.contains('during backup')) {
        return 'Conexão perdida durante o backup. '
            'O backup pode ter continuado no servidor.';
      }
      return 'Você foi desconectado do servidor. '
          'Reconecte-se para continuar.';
    }

    if ((message.contains('conclusão do backup') ||
            message.contains('conclusao do backup')) &&
        message.contains('limite')) {
      final limitMatch = _timeLimitMinutesPattern.firstMatch(message);
      final minutes = limitMatch?.group(1) ?? '10';
      return 'O backup passou do tempo limite ($minutes min). '
          'Verifique no servidor se foi concluído.';
    }

    if (lower.contains('timeout') || message.contains('TimeoutException')) {
      return 'Tempo esgotado ao aguardar resposta do servidor.';
    }

    if (message.contains('Resposta inesperada')) {
      return 'Resposta inesperada do servidor. Tente novamente.';
    }

    if (message.contains('Erro desconhecido')) {
      return 'Erro no servidor: $message';
    }

    return message.isNotEmpty ? message : _unknownErrorMessage;
  }
}

/// Backwards-compatible alias. Novos chamadores devem usar
/// `ErrorMessageMapper.mapToUserMessage`.
String mapExceptionToMessage(Object? exception) =>
    ErrorMessageMapper.mapToUserMessage(exception);
