import 'package:result_dart/result_dart.dart';

abstract class IWindowsServiceService {
  Future<Result<WindowsServiceStatus>> getStatus();

  Future<Result<void>> installService({
    String? serviceUser,
    String? servicePassword,
  });

  Future<Result<void>> uninstallService();

  Future<Result<void>> startService();

  Future<Result<void>> stopService();

  Future<Result<void>> restartService();
}

enum WindowsServiceStateCode {
  stopped(1),
  startPending(2),
  stopPending(3),
  running(4),
  continuePending(5),
  pausePending(6),
  paused(7)
  ;

  const WindowsServiceStateCode(this.code);
  final int code;

  static WindowsServiceStateCode? fromCode(int code) {
    for (final s in WindowsServiceStateCode.values) {
      if (s.code == code) return s;
    }
    return null;
  }

  bool get isRunning => this == WindowsServiceStateCode.running;
  bool get isPaused => this == WindowsServiceStateCode.paused;
}

class WindowsServiceStatus {
  const WindowsServiceStatus({
    required this.isInstalled,
    required this.isRunning,
    this.stateCode,
    this.serviceName,
    this.displayName,
  });
  final bool isInstalled;
  final bool isRunning;
  final WindowsServiceStateCode? stateCode;
  final String? serviceName;
  final String? displayName;
}
