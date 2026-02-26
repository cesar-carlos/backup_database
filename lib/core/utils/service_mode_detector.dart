import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class ServiceModeDetector {
  static const int _serviceSessionId = 0;
  static const String _serviceArgFlag = '--mode=server';

  static bool _isServiceMode = false;
  static bool _checked = false;

  static bool isServiceMode() {
    if (_checked) {
      return _isServiceMode;
    }

    _checked = true;

    if (!Platform.isWindows) {
      _isServiceMode = false;
      return false;
    }

    // Camada 1: argumento explícito (mais confiável quando injetado pelo NSSM).
    if (_hasServiceArgument(Platform.executableArguments)) {
      _isServiceMode = true;
      LoggerService.info('Modo Servico detectado (argumento --mode=server)');
      return true;
    }

    try {
      final processId = GetCurrentProcessId();

      final sessionId = calloc<DWORD>();
      try {
        final result = ProcessIdToSessionId(processId, sessionId);
        final isSessionLookupSuccessful = isSessionLookupSuccessfulForTest(
          result,
        );

        if (isSessionLookupSuccessful) {
          final sid = sessionId.value;
          LoggerService.debug('Process Session ID: $sid');

          _isServiceMode = isServiceSessionIdForTest(sid);

          if (_isServiceMode) {
            LoggerService.info('Modo Servico detectado (Session 0)');
          }
        } else {
          final lastError = GetLastError();
          LoggerService.debug(
            'Falha ao obter Session ID (retorno: $result, erro: $lastError). '
            'Tentando variavel de ambiente.',
          );
        }
      } finally {
        calloc.free(sessionId);
      }

      // Camada 3: variáveis de ambiente injetadas pelo NSSM.
      if (!_isServiceMode) {
        final serviceEnv =
            Platform.environment['SERVICE_NAME'] ??
            Platform.environment['NSSM_SERVICE'];
        if (serviceEnv != null && serviceEnv.isNotEmpty) {
          _isServiceMode = true;
          LoggerService.info('Modo Servico detectado (variavel de ambiente)');
        }
      }

      return _isServiceMode;
    } on Object catch (e) {
      LoggerService.warning('Erro ao detectar modo servico: $e');
      _isServiceMode = false;
      return false;
    }
  }

  static bool isSessionLookupSuccessfulForTest(int result) => result != 0;

  static bool isServiceSessionIdForTest(int sessionId) =>
      sessionId == _serviceSessionId;

  /// Verifica se a lista de argumentos contém a flag de modo serviço.
  static bool _hasServiceArgument(List<String> args) =>
      args.contains(_serviceArgFlag);
}
