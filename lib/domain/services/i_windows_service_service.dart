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

class WindowsServiceStatus {
  const WindowsServiceStatus({
    required this.isInstalled,
    required this.isRunning,
    this.serviceName,
    this.displayName,
  });
  final bool isInstalled;
  final bool isRunning;
  final String? serviceName;
  final String? displayName;
}
