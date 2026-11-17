import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

enum WindowsServicePresence { absent, installed, unknown }

class ServicePresenceResult {
  const ServicePresenceResult(this.presence, {this.errorCode});

  /// Only OpenService's ERROR_SERVICE_DOES_NOT_EXIST proves absence.
  /// In particular, access denied and marked-for-delete are not absence.
  factory ServicePresenceResult.fromOpenServiceError(int errorCode) =>
      ServicePresenceResult(
        errorCode == 1060
            ? WindowsServicePresence.absent
            : WindowsServicePresence.unknown,
        errorCode: errorCode,
      );

  final WindowsServicePresence presence;
  final int? errorCode;
}

/// Boot only needs existence, not state, shell output or administrator rights.
/// Prefer native SCM; a bounded, shell-free query confirms inconclusive results.
class WindowsServicePresenceProbe {
  WindowsServicePresenceProbe({ServicePresenceResult Function()? query})
    : _query = query ?? queryNative;

  final ServicePresenceResult Function() _query;
  final List<String> diagnostics = [];

  ServicePresenceResult read() {
    diagnostics.clear();
    try {
      final result = _query();
      diagnostics.add(
        'source=native presence=${result.presence.name} error=${result.errorCode}',
      );
      return result;
    } on Object catch (e, s) {
      diagnostics.add('source=native presence=unknown exception=$e');
      LoggerService.warning('event=service_presence_native_failed', e, s);
      return const ServicePresenceResult(WindowsServicePresence.unknown);
    }
  }

  /// A failed native query is not proof that a service exists. Independently
  /// confirm it through SCM before choosing the process execution role.
  Future<ServicePresenceResult> resolve({
    Future<int> Function()? queryExitCode,
  }) async {
    final native = read();
    if (native.presence != WindowsServicePresence.unknown) return native;
    LoggerService.warning(
      'event=service_presence_retry source=native error=${native.errorCode}',
    );
    try {
      final code = await (queryExitCode ?? _queryScExitCode)();
      final result = code == 0
          ? const ServicePresenceResult(WindowsServicePresence.installed)
          : ServicePresenceResult.fromOpenServiceError(code);
      diagnostics.add(
        'source=scm_cli presence=${result.presence.name} error=$code',
      );
      LoggerService.info(
        'event=service_presence_fallback source=scm_cli '
        'presence=${result.presence.name} error=$code',
      );
      return result;
    } on Object catch (e, s) {
      diagnostics.add('source=scm_cli presence=unknown exception=$e');
      LoggerService.warning('event=service_presence_fallback_failed', e, s);
      return native;
    }
  }

  static Future<int> _queryScExitCode() async {
    if (!Platform.isWindows) throw UnsupportedError('Windows SCM required');
    final root = Platform.environment['SystemRoot'];
    if (root == null || root.isEmpty) {
      throw StateError('SystemRoot unavailable');
    }
    // Do not search PATH, invoke a shell, or interpret localized console text.
    final process = await Process.start(
      '$root\\System32\\sc.exe',
      ['query', WindowsServiceConstants.serviceName],
    );
    final output = Future.wait([
      process.stdout.drain<void>(),
      process.stderr.drain<void>(),
    ]);
    try {
      return await process.exitCode.timeout(const Duration(seconds: 5));
    } finally {
      process.kill();
      await output.timeout(const Duration(seconds: 1), onTimeout: () => []);
    }
  }

  static ServicePresenceResult queryNative({
    String serviceName = WindowsServiceConstants.serviceName,
  }) {
    if (!Platform.isWindows) {
      return const ServicePresenceResult(WindowsServicePresence.unknown);
    }
    const managerConnect = 0x0001;
    const queryStatus = 0x0004;
    final manager = OpenSCManager(null, null, managerConnect);
    if (!manager.value.isValid) {
      return ServicePresenceResult(
        WindowsServicePresence.unknown,
        errorCode: manager.error.code,
      );
    }
    try {
      final service = using(
        (arena) => OpenService(
          manager.value,
          arena.pcwstr(serviceName),
          queryStatus,
        ),
      );
      if (!service.value.isValid) {
        return ServicePresenceResult.fromOpenServiceError(service.error.code);
      }
      service.value.close();
      return const ServicePresenceResult(WindowsServicePresence.installed);
    } finally {
      manager.value.close();
    }
  }
}
