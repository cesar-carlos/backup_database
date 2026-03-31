import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/compatibility/feature_availability_snapshot.dart';
import 'package:backup_database/core/compatibility/windows_compatibility_policy.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/system/os_version_checker.dart';
import 'package:backup_database/infrastructure/external/system/windows_runtime_environment.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:get_it/get_it.dart';

const _webviewProbeTimeout = Duration(seconds: 3);

class _WebviewRuntimeProbeResult {
  const _WebviewRuntimeProbeResult({
    required this.available,
    required this.timedOut,
  });

  final bool available;
  final bool timedOut;
}

abstract final class _WebviewRuntimeProbe {
  static _WebviewRuntimeProbeResult? _cached;

  static Future<_WebviewRuntimeProbeResult> check() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }

    try {
      final available = await WebviewWindow.isWebviewAvailable().timeout(
        _webviewProbeTimeout,
      );
      final result = _WebviewRuntimeProbeResult(
        available: available,
        timedOut: false,
      );
      _cached = result;
      return result;
    } on TimeoutException catch (e, s) {
      LoggerService.warning(
        'WebView2 probe timed out; treating runtime as unavailable',
        e,
        s,
      );
      const result = _WebviewRuntimeProbeResult(
        available: false,
        timedOut: true,
      );
      _cached = result;
      return result;
    } on Object catch (e, s) {
      LoggerService.warning(
        'WebView2 availability probe failed; treating runtime as unavailable',
        e,
        s,
      );
      const result = _WebviewRuntimeProbeResult(
        available: false,
        timedOut: false,
      );
      _cached = result;
      return result;
    }
  }
}

Future<void> registerFeatureAvailability(GetIt getIt) async {
  if (getIt.isRegistered<FeatureAvailabilityService>()) {
    return;
  }

  if (!Platform.isWindows) {
    final nonWindowsSnapshot = FeatureAvailabilitySnapshot.nonWindows();
    getIt.registerSingleton<FeatureAvailabilityService>(
      FeatureAvailabilityService(nonWindowsSnapshot),
    );
    LoggerService.info(nonWindowsSnapshot.toDiagnosticString());
    return;
  }

  final webviewProbeResult = await _WebviewRuntimeProbe.check();
  final sessionName = Platform.environment['SESSIONNAME'];

  final snapshot = OsVersionChecker.getVersionInfo().fold(
    (OsVersionInfo info) {
      final runtimeEnvironment = WindowsRuntimeEnvironment.detect(
        majorVersion: info.majorVersion,
        minorVersion: info.minorVersion,
        sessionName: sessionName,
      );
      return WindowsCompatibilityPolicy.fromOsVersionInfo(
        info: info,
        isServerLikely: runtimeEnvironment.isServer,
        serverDetectionReliable: runtimeEnvironment.isServerDetectionReliable,
        isInteractiveSessionLikely:
            runtimeEnvironment.isInteractiveSessionLikely,
        interactiveDetectionReliable:
            runtimeEnvironment.isInteractiveDetectionReliable,
        webviewRuntimeAvailable: webviewProbeResult.available,
        webviewProbeTimedOut: webviewProbeResult.timedOut,
      );
    },
    (_) => WindowsCompatibilityPolicy.conservativeFallback(
      webviewRuntimeAvailable: webviewProbeResult.available,
      webviewProbeTimedOut: webviewProbeResult.timedOut,
    ),
  );

  getIt.registerSingleton<FeatureAvailabilityService>(
    FeatureAvailabilityService(snapshot),
  );
  LoggerService.info(snapshot.toDiagnosticString());
}
