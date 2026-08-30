import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/http_error_helpers.dart';
import 'package:backup_database/core/utils/integrity_failure_messages.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class GoogleDriveErrors {
  GoogleDriveErrors._();

  /// Mapeia uma exceção do upload Google Drive para mensagem amigável.
  ///
  /// Estratégia em camadas (igual ao padrão FTP, ver
  /// `FtpDestinationService.getFtpErrorMessage`):
  /// 1. **Failure de integridade** (`integrity*` codes) — mensagem específica.
  /// 2. **Tipo específico** (`drive.DetailedApiRequestError` com `.status`,
  ///    `TimeoutException`, `SocketException`).
  /// 3. **Heurística por substring** com word‑boundary para códigos HTTP
  ///    (evita "11401" matchear como 401).
  static String describe(Object? e) {
    final integrity = IntegrityFailureMessages.tryDescribe(
      e,
      serviceName: 'Google Drive',
    );
    if (integrity != null) return integrity;
    if (e is TimeoutException) {
      return 'Tempo limite excedido ao enviar para o Google Drive.\n'
          'Para arquivos grandes, o upload pode levar vários minutos.\n'
          'Tente novamente ou verifique sua conexão.';
    }
    if (e is SocketException) {
      return 'Erro de conexão com o Google Drive.\n'
          'Verifique sua conexão com a internet.\n'
          'Detalhes: ${e.message}';
    }
    if (e is drive.DetailedApiRequestError && e.status != null) {
      final fromStatus = _messageByStatus(e.status!);
      if (fromStatus != null) return fromStatus;
    }

    final errorStr = e?.toString().toLowerCase() ?? '';

    final statusMatch = HttpErrorHelpers.firstHttpStatusIn(errorStr, const [
      401,
      403,
      404,
      413,
    ]);
    if (statusMatch != null) {
      final fromStatus = _messageByStatus(statusMatch);
      if (fromStatus != null) return fromStatus;
    }
    if (errorStr.contains('unauthorized')) {
      return 'Sessão do Google Drive expirada.\n'
          'Faça login novamente nas configurações.';
    }
    if (errorStr.contains('forbidden')) {
      return 'Sem permissão para acessar o Google Drive.\n'
          'Verifique se as permissões foram concedidas.';
    }
    if (errorStr.contains('not found')) {
      return 'Pasta de destino não encontrada no Google Drive.\n'
          'Verifique se a pasta ainda existe.';
    }
    if (errorStr.contains('quota') || errorStr.contains('limit exceeded')) {
      return 'Limite de armazenamento do Google Drive atingido.\n'
          'Libere espaço ou faça upgrade do plano.';
    }
    if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Erro de conexão com o Google Drive.\n'
          'Verifique sua conexão com a internet.';
    }
    if (errorStr.contains('timeout')) {
      return 'Tempo limite excedido ao enviar para o Google Drive.\n'
          'Para arquivos grandes, o upload pode levar vários minutos.\n'
          'Tente novamente ou verifique sua conexão.';
    }
    if (errorStr.contains('request entity too large')) {
      return 'Arquivo muito grande para upload direto.\n'
          'O Google Drive suporta arquivos de até 5TB, mas o upload pode demorar.';
    }

    return 'Erro no upload para o Google Drive após várias tentativas.\n'
        'Detalhes: $e';
  }

  static String? _messageByStatus(int status) {
    switch (status) {
      case 401:
        return 'Sessão do Google Drive expirada.\n'
            'Faça login novamente nas configurações.';
      case 403:
        return 'Sem permissão para acessar o Google Drive.\n'
            'Verifique se as permissões foram concedidas.';
      case 404:
        return 'Pasta de destino não encontrada no Google Drive.\n'
            'Verifique se a pasta ainda existe.';
      case 413:
        return 'Arquivo muito grande para upload direto.\n'
            'O Google Drive suporta arquivos de até 5TB, mas o upload pode demorar.';
      default:
        return null;
    }
  }
}
