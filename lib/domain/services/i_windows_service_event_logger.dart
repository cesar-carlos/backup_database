abstract class IWindowsServiceEventLogger {
  Future<void> logInstallStarted();
  Future<void> logInstallSucceeded();
  Future<void> logInstallFailed({required String error});
  Future<void> logStartStarted();
  Future<void> logStartSucceeded();
  Future<void> logStartFailed({required String error});
  Future<void> logStartTimeout({required Duration timeout});
  Future<void> logStopStarted();
  Future<void> logStopSucceeded();
  Future<void> logStopFailed({required String error});
  Future<void> logStopTimeout({required Duration timeout});
  Future<void> logUninstallStarted();
  Future<void> logUninstallSucceeded();
  Future<void> logUninstallFailed({required String error});
}
