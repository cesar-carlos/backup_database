import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/http_error_helpers.dart';
import 'package:backup_database/core/utils/integrity_failure_messages.dart';
import 'package:dio/dio.dart';

class NextcloudErrors {
  NextcloudErrors._();

  /// Mapeia uma exceção do upload Nextcloud para mensagem amigável.
  ///
  /// Mesma estratégia em camadas do FTP/Drive/Dropbox: integridade →
  /// tipo (`TimeoutException`/`HandshakeException`/`SocketException`/
  /// `DioException.statusCode`) → heurística por substring com
  /// word‑boundary em códigos HTTP.
  static String describe(Object? e) {
    final integrity = IntegrityFailureMessages.tryDescribe(
      e,
      serviceName: 'Nextcloud',
    );
    if (integrity != null) return integrity;
    if (e is TimeoutException) {
      return 'Tempo limite excedido ao enviar para o Nextcloud.\n'
          'Tente novamente ou verifique sua conexão.';
    }
    if (e is HandshakeException || e is TlsException) {
      return 'Falha de certificado TLS.\n'
          'Se o servidor usa certificado self-signed, habilite a opção '
          '"aceitar certificados inválidos".\n'
          'Detalhes: $e';
    }
    if (e is SocketException) {
      return 'Erro de conexão com o Nextcloud.\n'
          'Verifique sua conexão e a URL do servidor.\n'
          'Detalhes: ${e.message}';
    }
    if (e is DioException) {
      final code = e.response?.statusCode;
      final fromStatus = code == null ? null : _messageByStatus(code);
      if (fromStatus != null) return fromStatus;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Tempo limite excedido ao enviar para o Nextcloud.\n'
            'Tente novamente ou verifique sua conexão.';
      }
    }

    final errorStr = e?.toString().toLowerCase() ?? '';

    final statusMatch = HttpErrorHelpers.firstHttpStatusIn(errorStr, const [
      401,
      403,
      507,
    ]);
    if (statusMatch != null) {
      final fromStatus = _messageByStatus(statusMatch);
      if (fromStatus != null) return fromStatus;
    }
    if (errorStr.contains('unauthorized')) {
      return _messageByStatus(401)!;
    }
    if (errorStr.contains('forbidden')) {
      return _messageByStatus(403)!;
    }
    if (errorStr.contains('insufficient')) {
      return _messageByStatus(507)!;
    }
    if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao enviar para o Nextcloud.\n'
          'Tente novamente ou verifique sua conexão.';
    }
    if (errorStr.contains('certificate') || errorStr.contains('handshake')) {
      return 'Falha de certificado TLS.\n'
          'Se o servidor usa certificado self-signed, habilite a opção '
          '"aceitar certificados inválidos".';
    }
    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Erro de conexão com o Nextcloud.\n'
          'Verifique sua conexão e a URL do servidor.';
    }

    return 'Erro no Nextcloud após várias tentativas.\n'
        'Detalhes: $e';
  }

  static String? _messageByStatus(int status) {
    switch (status) {
      case 401:
        return 'Credenciais inválidas ou sessão expirada.\n'
            'Verifique o usuário e o App Password.';
      case 403:
        return 'Sem permissão para acessar o Nextcloud.\n'
            'Verifique as permissões do usuário.';
      case 507:
        return 'Armazenamento insuficiente no Nextcloud.\n'
            'Libere espaço ou aumente a cota.';
      default:
        return null;
    }
  }
}
