import 'package:backup_database/core/compatibility/feature_availability_snapshot.dart';
import 'package:backup_database/core/compatibility/feature_disable_reason.dart';
import 'package:backup_database/infrastructure/external/system/os_version_checker.dart'
    show OsVersionInfo;

abstract final class WindowsCompatibilityPolicy {
  static const int _minimumSupportedMajor = 6;
  static const int _minimumSupportedMinor = 2;

  static FeatureAvailabilitySnapshot compute({
    required int majorVersion,
    required int minorVersion,
    required bool isServerLikely,
    required bool serverDetectionReliable,
    required bool isInteractiveSessionLikely,
    required bool interactiveDetectionReliable,
    required bool webviewRuntimeAvailable,
    required bool webviewProbeTimedOut,
    required bool osVersionParseFailed,
  }) {
    final meetsMinimumOs =
        !osVersionParseFailed &&
        _isAtLeastMinimumSupportedVersion(
          majorVersion: majorVersion,
          minorVersion: minorVersion,
        );
    final minimumOsReason = osVersionParseFailed
        ? FeatureDisableReason.osVersionUnresolved
        : FeatureDisableReason.osBelowMinimum;

    final isLegacyServer =
        majorVersion == 6 && (minorVersion == 2 || minorVersion == 3);
    final isWindows10OrNewer = majorVersion >= 10;

    final taskSchedulerEnabled = meetsMinimumOs;
    final windowsServiceManagementEnabled = meetsMinimumOs;
    final startupAtLogonTaskEnabled = meetsMinimumOs;

    final windowManagementEnabled =
        meetsMinimumOs && isInteractiveSessionLikely;
    final trayEnabled = meetsMinimumOs && isInteractiveSessionLikely;

    FeatureDisableReason? autoReason;
    var autoUpdateEnabled = false;
    if (!meetsMinimumOs) {
      autoReason = minimumOsReason;
    } else if (isServerLikely && !isWindows10OrNewer) {
      autoReason = FeatureDisableReason.autoUpdateUnsupportedLegacyServer;
    } else {
      autoUpdateEnabled = true;
    }

    FeatureDisableReason? externalOAuthReason;
    var externalBrowserOAuthEnabled = false;
    if (!meetsMinimumOs) {
      externalOAuthReason = minimumOsReason;
    } else {
      externalBrowserOAuthEnabled = true;
    }

    FeatureDisableReason? embeddedReason;
    var embeddedWebviewOAuthEnabled = false;
    if (!meetsMinimumOs) {
      embeddedReason = minimumOsReason;
    } else if (webviewProbeTimedOut) {
      embeddedReason = FeatureDisableReason.webviewProbeTimedOut;
    } else if (!webviewRuntimeAvailable) {
      embeddedReason = FeatureDisableReason.webviewRuntimeUnavailable;
    } else if (isServerLikely && isLegacyServer) {
      embeddedReason =
          FeatureDisableReason.embeddedWebviewUnsupportedLegacyServer;
    } else {
      embeddedWebviewOAuthEnabled = true;
    }

    FeatureDisableReason? taskSchedulerReason;
    FeatureDisableReason? windowsServiceReason;
    FeatureDisableReason? startupTaskReason;
    FeatureDisableReason? windowManagementReason;
    FeatureDisableReason? trayReason;
    if (!meetsMinimumOs) {
      taskSchedulerReason = minimumOsReason;
      windowsServiceReason = taskSchedulerReason;
      startupTaskReason = taskSchedulerReason;
      windowManagementReason = taskSchedulerReason;
      trayReason = taskSchedulerReason;
    } else if (!isInteractiveSessionLikely) {
      windowManagementReason =
          FeatureDisableReason.windowManagementRequiresInteractiveSession;
      trayReason = FeatureDisableReason.trayRequiresInteractiveSession;
    }

    return FeatureAvailabilitySnapshot(
      isWindows: true,
      majorVersion: majorVersion,
      minorVersion: minorVersion,
      isServerLikely: isServerLikely,
      serverDetectionReliable: serverDetectionReliable,
      isInteractiveSessionLikely: isInteractiveSessionLikely,
      interactiveDetectionReliable: interactiveDetectionReliable,
      osVersionParseFailed: osVersionParseFailed,
      webviewRuntimeAvailable: webviewRuntimeAvailable,
      webviewProbeTimedOut: webviewProbeTimedOut,
      autoUpdateEnabled: autoUpdateEnabled,
      windowManagementEnabled: windowManagementEnabled,
      trayEnabled: trayEnabled,
      taskSchedulerEnabled: taskSchedulerEnabled,
      windowsServiceManagementEnabled: windowsServiceManagementEnabled,
      startupAtLogonTaskEnabled: startupAtLogonTaskEnabled,
      externalBrowserOAuthEnabled: externalBrowserOAuthEnabled,
      embeddedWebviewOAuthEnabled: embeddedWebviewOAuthEnabled,
      autoUpdateDisabledReason: autoReason,
      externalBrowserOAuthDisabledReason: externalOAuthReason,
      embeddedWebviewDisabledReason: embeddedReason,
      taskSchedulerDisabledReason: taskSchedulerEnabled
          ? null
          : taskSchedulerReason,
      windowsServiceManagementDisabledReason: windowsServiceManagementEnabled
          ? null
          : windowsServiceReason,
      startupAtLogonTaskDisabledReason: startupAtLogonTaskEnabled
          ? null
          : startupTaskReason,
      windowManagementDisabledReason: windowManagementEnabled
          ? null
          : windowManagementReason,
      trayDisabledReason: trayEnabled ? null : trayReason,
    );
  }

  static FeatureAvailabilitySnapshot fromOsVersionInfo({
    required OsVersionInfo info,
    required bool isServerLikely,
    required bool serverDetectionReliable,
    required bool isInteractiveSessionLikely,
    required bool interactiveDetectionReliable,
    required bool webviewRuntimeAvailable,
    required bool webviewProbeTimedOut,
  }) {
    return compute(
      majorVersion: info.majorVersion,
      minorVersion: info.minorVersion,
      isServerLikely: isServerLikely,
      serverDetectionReliable: serverDetectionReliable,
      isInteractiveSessionLikely: isInteractiveSessionLikely,
      interactiveDetectionReliable: interactiveDetectionReliable,
      webviewRuntimeAvailable: webviewRuntimeAvailable,
      webviewProbeTimedOut: webviewProbeTimedOut,
      osVersionParseFailed: false,
    );
  }

  static FeatureAvailabilitySnapshot conservativeFallback({
    required bool webviewRuntimeAvailable,
    required bool webviewProbeTimedOut,
  }) {
    return compute(
      majorVersion: 6,
      minorVersion: 3,
      isServerLikely: true,
      serverDetectionReliable: false,
      isInteractiveSessionLikely: false,
      interactiveDetectionReliable: false,
      webviewRuntimeAvailable: webviewRuntimeAvailable,
      webviewProbeTimedOut: webviewProbeTimedOut,
      osVersionParseFailed: true,
    );
  }

  static bool _isAtLeastMinimumSupportedVersion({
    required int majorVersion,
    required int minorVersion,
  }) {
    if (majorVersion > _minimumSupportedMajor) {
      return true;
    }
    if (majorVersion < _minimumSupportedMajor) {
      return false;
    }
    return minorVersion >= _minimumSupportedMinor;
  }
}
