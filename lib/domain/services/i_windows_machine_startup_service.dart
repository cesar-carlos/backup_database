class WindowsMachineStartupOutcome {
  const WindowsMachineStartupOutcome({
    required this.ok,
    this.diagnostics = '',
  });

  final bool ok;
  final String diagnostics;
}

class WindowsMachineStartupInspection {
  const WindowsMachineStartupInspection({
    required this.ok,
    required this.hasLegacyRunEntry,
    required this.hasScheduledTask,
    this.diagnostics = '',
    this.needsStartupLaunchProtocolMigration = false,
  });

  final bool ok;
  final bool hasLegacyRunEntry;
  final bool hasScheduledTask;
  final String diagnostics;
  final bool needsStartupLaunchProtocolMigration;
}

abstract class IWindowsMachineStartupService {
  /// Inspects current Windows startup artifacts without mutating them.
  Future<WindowsMachineStartupInspection> inspect();

  /// Applies machine-scope startup registration on Windows.
  ///
  /// Always removes legacy `HKCU\...\Run\BackupDatabase` and any existing
  /// machine startup task when [enabled] is false, or before re-creating
  /// the task when [enabled] is true.
  ///
  /// When [installScheduledTask] is false (server UI mode), does not register
  /// a logon task; Windows Service is the supported autostart path.
  Future<WindowsMachineStartupOutcome> apply({
    required bool enabled,
    required bool installScheduledTask,
    required String executablePath,
    required String taskArguments,
  });
}
