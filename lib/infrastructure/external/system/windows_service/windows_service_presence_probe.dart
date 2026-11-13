import 'dart:io';

import 'package:backup_database/core/constants/windows_service_constants.dart';
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
/// Keeping this independent of sc.exe also avoids PATH and encoding failures.
class WindowsServicePresenceProbe {
  WindowsServicePresenceProbe({ServicePresenceResult Function()? query})
    : _query = query ?? queryNative;

  final ServicePresenceResult Function() _query;

  ServicePresenceResult read() {
    try {
      return _query();
    } on Object {
      return const ServicePresenceResult(WindowsServicePresence.unknown);
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
