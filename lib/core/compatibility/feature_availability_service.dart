import 'package:backup_database/core/compatibility/feature_availability_snapshot.dart';
import 'package:backup_database/core/compatibility/feature_disable_reason.dart';

class FeatureAvailabilityService {
  FeatureAvailabilityService(this.snapshot);

  final FeatureAvailabilitySnapshot snapshot;

  bool get isAutoUpdateEnabled => snapshot.autoUpdateEnabled;

  FeatureDisableReason? get autoUpdateDisabledReason =>
      snapshot.autoUpdateDisabledReason;

  bool get isWindowManagementEnabled => snapshot.windowManagementEnabled;

  FeatureDisableReason? get windowManagementDisabledReason =>
      snapshot.windowManagementDisabledReason;

  bool get isTrayEnabled => snapshot.trayEnabled;

  FeatureDisableReason? get trayDisabledReason => snapshot.trayDisabledReason;

  bool get isTaskSchedulerEnabled => snapshot.taskSchedulerEnabled;

  FeatureDisableReason? get taskSchedulerDisabledReason =>
      snapshot.taskSchedulerDisabledReason;

  bool get isWindowsServiceManagementEnabled =>
      snapshot.windowsServiceManagementEnabled;

  FeatureDisableReason? get windowsServiceManagementDisabledReason =>
      snapshot.windowsServiceManagementDisabledReason;

  bool get isStartupAtLogonTaskEnabled => snapshot.startupAtLogonTaskEnabled;

  FeatureDisableReason? get startupAtLogonTaskDisabledReason =>
      snapshot.startupAtLogonTaskDisabledReason;

  bool get isExternalBrowserOAuthEnabled =>
      snapshot.externalBrowserOAuthEnabled;

  FeatureDisableReason? get externalBrowserOAuthDisabledReason =>
      snapshot.externalBrowserOAuthDisabledReason;

  bool get isEmbeddedWebviewOAuthEnabled =>
      snapshot.embeddedWebviewOAuthEnabled;

  FeatureDisableReason? get embeddedWebviewOAuthDisabledReason =>
      snapshot.embeddedWebviewDisabledReason;

  bool get isInteractiveSessionLikely => snapshot.isInteractiveSessionLikely;

  bool get osVersionParseFailed => snapshot.osVersionParseFailed;

  String diagnosticSummary() => snapshot.toDiagnosticString();
}
