import 'dart:ffi';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WindowsRuntimeEnvironment {
  static const int _serviceSessionId = 0;
  static const String _servicesSessionName = 'services';

  static WindowsRuntimeEnvironmentInfo detect({
    required int majorVersion,
    required int minorVersion,
    required String? sessionName,
  }) {
    final serverResult = _detectServerByNativeApi(
      majorVersion: majorVersion,
      minorVersion: minorVersion,
    );
    final interactiveResult = _detectInteractiveSession(
      sessionName: sessionName,
    );

    return WindowsRuntimeEnvironmentInfo(
      isServer: serverResult.value,
      isServerDetectionReliable: !serverResult.usedFallback,
      isInteractiveSessionLikely: interactiveResult.value,
      isInteractiveDetectionReliable: !interactiveResult.usedFallback,
    );
  }

  static _DetectionResult _detectServerByNativeApi({
    required int majorVersion,
    required int minorVersion,
  }) {
    final osVersionInfo = calloc<OSVERSIONINFOEX>();
    try {
      osVersionInfo.ref.dwOSVersionInfoSize = sizeOf<OSVERSIONINFOEX>();
      final callResult = GetVersionEx(
        osVersionInfo.cast<OSVERSIONINFO>(),
      );
      if (callResult != 0) {
        final productType = osVersionInfo.ref.wProductType;
        final isServer = productType != VER_NT_WORKSTATION;
        return _DetectionResult(value: isServer, usedFallback: false);
      }
      final lastError = GetLastError();
      LoggerService.warning(
        '[WindowsRuntimeEnvironment] GetVersionEx failed, '
        'error=$lastError. Falling back to OS string classification.',
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        '[WindowsRuntimeEnvironment] Native server detection failed. '
        'Falling back to OS string classification.',
        e,
        s,
      );
    } finally {
      calloc.free(osVersionInfo);
    }

    // Conservative fallback:
    // Server SKUs before Windows 10 generally report NT 6.x.
    final isLegacyServerLikely = majorVersion == 6 && minorVersion >= 2;
    return _DetectionResult(value: isLegacyServerLikely, usedFallback: true);
  }

  static _DetectionResult _detectInteractiveSession({
    required String? sessionName,
  }) {
    final sessionIdBuffer = calloc<DWORD>();
    try {
      final currentPid = GetCurrentProcessId();
      final processToSessionResult = ProcessIdToSessionId(
        currentPid,
        sessionIdBuffer,
      );
      if (processToSessionResult == 0) {
        final lastError = GetLastError();
        LoggerService.warning(
          '[WindowsRuntimeEnvironment] ProcessIdToSessionId failed, '
          'error=$lastError. Falling back to SESSIONNAME heuristic.',
        );
        return _detectInteractiveByEnvironment(sessionName: sessionName);
      }

      final sessionId = sessionIdBuffer.value;
      final hasExplorerShell = GetShellWindow() != NULL;
      final hasInteractiveSessionName =
          sessionName != null &&
          sessionName.trim().isNotEmpty &&
          sessionName.trim().toLowerCase() != _servicesSessionName;
      final isInteractive =
          sessionId != _serviceSessionId &&
          (hasExplorerShell || hasInteractiveSessionName);

      return _DetectionResult(value: isInteractive, usedFallback: false);
    } on Object catch (e, s) {
      LoggerService.warning(
        '[WindowsRuntimeEnvironment] Native interactive detection failed. '
        'Falling back to SESSIONNAME heuristic.',
        e,
        s,
      );
      return _detectInteractiveByEnvironment(sessionName: sessionName);
    } finally {
      calloc.free(sessionIdBuffer);
    }
  }

  static _DetectionResult _detectInteractiveByEnvironment({
    required String? sessionName,
  }) {
    final normalized = sessionName?.trim().toLowerCase();
    final isInteractive =
        normalized != null &&
        normalized.isNotEmpty &&
        normalized != _servicesSessionName;
    return _DetectionResult(value: isInteractive, usedFallback: true);
  }
}

class WindowsRuntimeEnvironmentInfo {
  const WindowsRuntimeEnvironmentInfo({
    required this.isServer,
    required this.isServerDetectionReliable,
    required this.isInteractiveSessionLikely,
    required this.isInteractiveDetectionReliable,
  });

  final bool isServer;
  final bool isServerDetectionReliable;
  final bool isInteractiveSessionLikely;
  final bool isInteractiveDetectionReliable;
}

class _DetectionResult {
  const _DetectionResult({required this.value, required this.usedFallback});

  final bool value;
  final bool usedFallback;
}
