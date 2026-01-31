import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class ServiceModeDetector {
  static bool _isServiceMode = false;
  static bool _checked = false;

  static bool isServiceMode() {
    if (_checked) return _isServiceMode;

    _checked = true;

    if (!Platform.isWindows) {
      _isServiceMode = false;
      return false;
    }

    try {
      final processId = GetCurrentProcessId();

      final sessionId = calloc<DWORD>();
      try {
        final result = ProcessIdToSessionId(processId, sessionId);

        if (result == 0) {
          final sid = sessionId.value;
          LoggerService.debug('Process Session ID: $sid');

          _isServiceMode = sid == 0;

          if (_isServiceMode) {
            LoggerService.info('🔧 Modo Serviço detectado (Session 0)');
          }
        } else {
          LoggerService.debug(
            'Falha ao obter Session ID (código: $result), tentando variável '
            'de ambiente',
          );
        }
      } finally {
        calloc.free(sessionId);
      }

      if (!_isServiceMode) {
        final serviceEnv =
            Platform.environment['SERVICE_NAME'] ??
            Platform.environment['NSSM_SERVICE'];
        if (serviceEnv != null && serviceEnv.isNotEmpty) {
          _isServiceMode = true;
          LoggerService.info(
            '🔧 Modo Serviço detectado (variável de ambiente)',
          );
        }
      }

      return _isServiceMode;
    } on Object catch (e) {
      LoggerService.warning('Erro ao detectar modo serviço: $e');
      _isServiceMode = false;
      return false;
    }
  }
}
