import 'package:backup_database/core/compatibility/feature_disable_reason.dart';
import 'package:meta/meta.dart';

@immutable
class FeatureAvailabilitySnapshot {
  const FeatureAvailabilitySnapshot({
    required this.isWindows,
    required this.majorVersion,
    required this.minorVersion,
    required this.isServerLikely,
    required this.serverDetectionReliable,
    required this.isInteractiveSessionLikely,
    required this.interactiveDetectionReliable,
    required this.osVersionParseFailed,
    required this.webviewRuntimeAvailable,
    required this.webviewProbeTimedOut,
    required this.autoUpdateEnabled,
    required this.windowManagementEnabled,
    required this.trayEnabled,
    required this.taskSchedulerEnabled,
    required this.windowsServiceManagementEnabled,
    required this.startupAtLogonTaskEnabled,
    required this.externalBrowserOAuthEnabled,
    required this.embeddedWebviewOAuthEnabled,
    this.autoUpdateDisabledReason,
    this.externalBrowserOAuthDisabledReason,
    this.embeddedWebviewDisabledReason,
    this.taskSchedulerDisabledReason,
    this.windowsServiceManagementDisabledReason,
    this.startupAtLogonTaskDisabledReason,
    this.windowManagementDisabledReason,
    this.trayDisabledReason,
  });

  final bool isWindows;
  final int majorVersion;
  final int minorVersion;
  final bool isServerLikely;
  final bool serverDetectionReliable;
  final bool isInteractiveSessionLikely;
  final bool interactiveDetectionReliable;
  final bool osVersionParseFailed;
  final bool webviewRuntimeAvailable;
  final bool webviewProbeTimedOut;

  final bool autoUpdateEnabled;
  final bool windowManagementEnabled;
  final bool trayEnabled;
  final bool taskSchedulerEnabled;
  final bool windowsServiceManagementEnabled;
  final bool startupAtLogonTaskEnabled;
  final bool externalBrowserOAuthEnabled;
  final bool embeddedWebviewOAuthEnabled;

  final FeatureDisableReason? autoUpdateDisabledReason;
  final FeatureDisableReason? externalBrowserOAuthDisabledReason;
  final FeatureDisableReason? embeddedWebviewDisabledReason;
  final FeatureDisableReason? taskSchedulerDisabledReason;
  final FeatureDisableReason? windowsServiceManagementDisabledReason;
  final FeatureDisableReason? startupAtLogonTaskDisabledReason;
  final FeatureDisableReason? windowManagementDisabledReason;
  final FeatureDisableReason? trayDisabledReason;

  factory FeatureAvailabilitySnapshot.nonWindows() {
    return const FeatureAvailabilitySnapshot(
      isWindows: false,
      majorVersion: 0,
      minorVersion: 0,
      isServerLikely: false,
      serverDetectionReliable: true,
      isInteractiveSessionLikely: false,
      interactiveDetectionReliable: true,
      osVersionParseFailed: false,
      webviewRuntimeAvailable: false,
      webviewProbeTimedOut: false,
      autoUpdateEnabled: false,
      windowManagementEnabled: false,
      trayEnabled: false,
      taskSchedulerEnabled: false,
      windowsServiceManagementEnabled: false,
      startupAtLogonTaskEnabled: false,
      externalBrowserOAuthEnabled: false,
      embeddedWebviewOAuthEnabled: false,
      autoUpdateDisabledReason: FeatureDisableReason.notWindows,
      externalBrowserOAuthDisabledReason: FeatureDisableReason.notWindows,
      embeddedWebviewDisabledReason: FeatureDisableReason.notWindows,
      taskSchedulerDisabledReason: FeatureDisableReason.notWindows,
      windowsServiceManagementDisabledReason: FeatureDisableReason.notWindows,
      startupAtLogonTaskDisabledReason: FeatureDisableReason.notWindows,
      windowManagementDisabledReason: FeatureDisableReason.notWindows,
      trayDisabledReason: FeatureDisableReason.notWindows,
    );
  }

  String toDiagnosticString() {
    final buffer = StringBuffer()
      ..writeln('[WindowsCompatibility]')
      ..writeln(
        '  os=Windows major=$majorVersion minor=$minorVersion '
        'serverLikely=$isServerLikely serverReliable=$serverDetectionReliable '
        'interactive=$isInteractiveSessionLikely '
        'interactiveReliable=$interactiveDetectionReliable '
        'osParseFailed=$osVersionParseFailed '
        'webview2=$webviewRuntimeAvailable '
        'webviewProbeTimedOut=$webviewProbeTimedOut',
      )
      ..writeln(
        '  autoUpdate=$autoUpdateEnabled '
        'window=$windowManagementEnabled tray=$trayEnabled '
        'schtasks=$taskSchedulerEnabled serviceUi=$windowsServiceManagementEnabled '
        'startupTask=$startupAtLogonTaskEnabled',
      )
      ..writeln(
        '  oauthExternal=$externalBrowserOAuthEnabled '
        'oauthEmbeddedWebview=$embeddedWebviewOAuthEnabled',
      );
    if (autoUpdateDisabledReason != null) {
      buffer.writeln(
        '  autoUpdateReason=${autoUpdateDisabledReason!.diagnosticLabel}',
      );
    }
    if (externalBrowserOAuthDisabledReason != null) {
      buffer.writeln(
        '  oauthExternalReason='
        '${externalBrowserOAuthDisabledReason!.diagnosticLabel}',
      );
    }
    if (embeddedWebviewDisabledReason != null) {
      buffer.writeln(
        '  oauthEmbeddedReason='
        '${embeddedWebviewDisabledReason!.diagnosticLabel}',
      );
    }
    if (taskSchedulerDisabledReason != null) {
      buffer.writeln(
        '  taskSchedulerReason=${taskSchedulerDisabledReason!.diagnosticLabel}',
      );
    }
    if (windowsServiceManagementDisabledReason != null) {
      buffer.writeln(
        '  windowsServiceReason='
        '${windowsServiceManagementDisabledReason!.diagnosticLabel}',
      );
    }
    if (startupAtLogonTaskDisabledReason != null) {
      buffer.writeln(
        '  startupTaskReason='
        '${startupAtLogonTaskDisabledReason!.diagnosticLabel}',
      );
    }
    if (windowManagementDisabledReason != null) {
      buffer.writeln(
        '  windowManagementReason='
        '${windowManagementDisabledReason!.diagnosticLabel}',
      );
    }
    if (trayDisabledReason != null) {
      buffer.writeln(
        '  trayReason=${trayDisabledReason!.diagnosticLabel}',
      );
    }
    return buffer.toString().trimRight();
  }
}
