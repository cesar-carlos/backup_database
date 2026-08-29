import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Headless Windows-service detection.
///
/// Contract shared with `windows/runner/main.cpp` `IsServiceMode`:
/// 1. Session 0 (Windows services have no interactive desktop).
/// 2. Exact argument `--run-as-service` (NSSM AppParameters).
/// 3. `SERVICE_MODE` in {server, 1, true} after lowercasing.
///    Dart also trims; the C++ runner does not.
class ServiceModeDetector {
  static const int _serviceSessionId = 0;
  static const String serviceArgFlag = '--run-as-service';

  /// Accepted values for the SERVICE_MODE environment variable.
  /// Rejects arbitrary strings to avoid false positives.
  static const Set<String> validServiceModeValues = {'server', '1', 'true'};

  static bool _isServiceMode = false;
  static bool _checked = false;

  /// Limpa o resultado memoizado da detecção. Existe apenas para
  /// permitir testes que exercitam múltiplos cenários de argumentos /
  /// ambiente em sequência — produção chama `isServiceMode` uma vez
  /// no boot e nunca mais.
  @visibleForTesting
  static void resetCacheForTest() {
    _isServiceMode = false;
    _checked = false;
  }

  static bool isServiceMode({List<String>? executableArguments}) {
    if (_checked) {
      return _isServiceMode;
    }

    _checked = true;

    final argsForServiceFlag =
        executableArguments ?? Platform.executableArguments;

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
        if (result.value) {
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
          LoggerService.warning(
            '[ServiceModeDetector] layer-1 failed: ProcessIdToSessionId '
            'returned false, GetLastError=${result.error}',
          );
        }
      } finally {
        calloc.free(sessionId);
      }

      // Layer 2: explicit --run-as-service argument injected by NSSM via
      // AppParameters. Semantically distinct from --mode=server (functional).
      if (matchesServiceArgument(argsForServiceFlag)) {
        _isServiceMode = true;
        LoggerService.info(
          '[ServiceModeDetector] MATCH layer-2: argument '
          '"$serviceArgFlag" → service mode',
        );
        return true;
      }
      LoggerService.info(
        '[ServiceModeDetector] layer-2 skip: argument '
        '"$serviceArgFlag" not present '
        '(args=$argsForServiceFlag)',
      );

      // Layer 3: SERVICE_MODE environment variable injected by NSSM via
      // AppEnvironmentExtra. Only accepted values: server | 1 | true.
      final rawServiceMode = Platform.environment['SERVICE_MODE'];
      if (matchesServiceModeEnvValue(rawServiceMode)) {
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
          '(accepted: ${validServiceModeValues.join(", ")})',
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
  @visibleForTesting
  static bool matchesServiceArgument(List<String> args) =>
      args.contains(serviceArgFlag);

  /// Returns true if [raw] is an accepted `SERVICE_MODE` value.
  /// Trims and lowercases; the C++ runner lowercases only.
  @visibleForTesting
  static bool matchesServiceModeEnvValue(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    return normalized != null && validServiceModeValues.contains(normalized);
  }
}
