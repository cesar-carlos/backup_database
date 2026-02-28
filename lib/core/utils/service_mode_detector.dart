import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class ServiceModeDetector {
  static const int _serviceSessionId = 0;
  static const String _serviceArgFlag = '--run-as-service';

  /// Accepted values for the SERVICE_MODE environment variable.
  /// Rejects arbitrary strings to avoid false positives.
  static const Set<String> _validServiceModeValues = {'server', '1', 'true'};

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

    try {
      // Layer 1: Session 0 — most reliable signal; Windows services always
      // run in Session 0, interactive user processes do not.
      final processId = GetCurrentProcessId();
      final sessionId = calloc<DWORD>();
      try {
        final result = ProcessIdToSessionId(processId, sessionId);
        if (result != 0) {
          final sid = sessionId.value;
          LoggerService.info('[ServiceModeDetector] Session ID: $sid');
          if (sid == _serviceSessionId) {
            _isServiceMode = true;
            LoggerService.info(
              '[ServiceModeDetector] MATCH layer-1: Session 0 → service mode',
            );
            return true;
          }
          LoggerService.info(
            '[ServiceModeDetector] layer-1 skip: Session $sid ≠ 0',
          );
        } else {
          final lastError = GetLastError();
          LoggerService.warning(
            '[ServiceModeDetector] layer-1 failed: ProcessIdToSessionId '
            'returned $result, GetLastError=$lastError',
          );
        }
      } finally {
        calloc.free(sessionId);
      }

      // Layer 2: explicit --run-as-service argument injected by NSSM via
      // AppParameters. Semantically distinct from --mode=server (functional).
      if (_hasServiceArgument(Platform.executableArguments)) {
        _isServiceMode = true;
        LoggerService.info(
          '[ServiceModeDetector] MATCH layer-2: argument '
          '"$_serviceArgFlag" → service mode',
        );
        return true;
      }
      LoggerService.info(
        '[ServiceModeDetector] layer-2 skip: argument '
        '"$_serviceArgFlag" not present '
        '(args=${Platform.executableArguments})',
      );

      // Layer 3: SERVICE_MODE environment variable injected by NSSM via
      // AppEnvironmentExtra. Only accepted values: server | 1 | true.
      final rawServiceMode = Platform.environment['SERVICE_MODE'];
      final normalizedServiceMode = rawServiceMode?.trim().toLowerCase();
      if (normalizedServiceMode != null &&
          _validServiceModeValues.contains(normalizedServiceMode)) {
        _isServiceMode = true;
        LoggerService.info(
          '[ServiceModeDetector] MATCH layer-3: env SERVICE_MODE="$rawServiceMode" '
          '→ service mode',
        );
        return true;
      }
      if (rawServiceMode != null) {
        LoggerService.warning(
          '[ServiceModeDetector] layer-3 skip: env SERVICE_MODE="$rawServiceMode" '
          'is not an accepted value '
          '(accepted: ${_validServiceModeValues.join(", ")})',
        );
      } else {
        LoggerService.info(
          '[ServiceModeDetector] layer-3 skip: SERVICE_MODE not set',
        );
      }

      // No rule matched.
      LoggerService.info(
        '[ServiceModeDetector] NO MATCH → UI mode',
      );
      _isServiceMode = false;
      return false;
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        '[ServiceModeDetector] detection error — defaulting to UI mode',
        e,
        stackTrace,
      );
      _isServiceMode = false;
      return false;
    }
  }

  static bool isSessionLookupSuccessfulForTest(int result) => result != 0;

  static bool isServiceSessionIdForTest(int sessionId) =>
      sessionId == _serviceSessionId;

  /// Returns true if [args] contains the dedicated service execution flag.
  static bool _hasServiceArgument(List<String> args) =>
      args.contains(_serviceArgFlag);
}
