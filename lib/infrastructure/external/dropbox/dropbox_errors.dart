import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/http_error_helpers.dart';
import 'package:backup_database/core/utils/integrity_failure_messages.dart';
import 'package:dio/dio.dart';

class DropboxErrors {
  DropboxErrors._();

  /// Mapeia uma exceção do upload Dropbox para mensagem amigável.
  ///
  /// Mesma estratégia em camadas do FTP/Drive: integridade → tipo
  /// (`TimeoutException`/`SocketException`/`DioException.statusCode`) →
  /// heurística por substring com word‑boundary em códigos HTTP.
  static String describe(Object? e) {
    final integrity = IntegrityFailureMessages.tryDescribe(
      e,
      serviceName: 'Dropbox',
    );
    if (integrity != null) return integrity;
    if (e is TimeoutException) {
      return 'Tempo limite excedido ao enviar para o Dropbox.\n'
          'Para arquivos grandes, o upload pode levar vários minutos.\n'
          'Tente novamente ou verifique sua conexão.';
    }
    if (e is SocketException) {
      return 'Erro de conexão com o Dropbox.\n'
          'Verifique sua conexão com a internet.\n'
          'Detalhes: ${e.message}';
    }
    if (e is DioException) {
      final code = e.response?.statusCode;
      final fromStatus = code == null ? null : _messageByStatus(code);
      if (fromStatus != null) return fromStatus;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Tempo limite excedido ao enviar para o Dropbox.\n'
            'Para arquivos grandes, o upload pode levar vários minutos.';
      }
    }

    final errorStr = e?.toString().toLowerCase() ?? '';

    final statusMatch = HttpErrorHelpers.firstHttpStatusIn(errorStr, const [
      401,
      403,
      409,
      507,
    ]);
    if (statusMatch != null) {
      final fromStatus = _messageByStatus(statusMatch);
      if (fromStatus != null) return fromStatus;
    }
    if (errorStr.contains('unauthorized')) {
      return 'Sessão do Dropbox expirada.\n'
          'Faça login novamente nas configurações.';
    }
    if (errorStr.contains('forbidden')) {
      return 'Sem permissão para acessar o Dropbox.\n'
          'Verifique se as permissões foram concedidas.';
    }
    if (errorStr.contains('path/conflict') ||
        errorStr.contains('insufficient_storage')) {
      // Casos específicos do Dropbox que viajam fora do statusCode.
      if (errorStr.contains('insufficient_storage')) {
        return _messageByStatus(507)!;
      }
      return _messageByStatus(409)!;
    }
    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Erro de conexão com o Dropbox.\n'
          'Verifique sua conexão com a internet.';
    }
    if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao enviar para o Dropbox.\n'
          'Para arquivos grandes, o upload pode levar vários minutos.';
    }

    return 'Erro no upload para o Dropbox após várias tentativas.\n'
        'Detalhes: $e';
  }

  static String? _messageByStatus(int status) {
    switch (status) {
      case 401:
        return 'Sessão do Dropbox expirada.\n'
            'Faça login novamente nas configurações.';
      case 403:
        return 'Sem permissão para acessar o Dropbox.\n'
            'Verifique se as permissões foram concedidas.';
      case 409:
        return 'Arquivo ou pasta já existe no Dropbox.\n'
            'O sistema tentará sobrescrever o arquivo automaticamente na próxima tentativa.';
      case 507:
        return 'Limite de armazenamento do Dropbox atingido.\n'
            'Libere espaço ou faça upgrade do plano.';
      default:
        return null;
    }
  }
}
