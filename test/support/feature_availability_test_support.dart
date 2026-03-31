import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/compatibility/feature_availability_snapshot.dart';
import 'package:backup_database/core/di/service_locator.dart';

const FeatureAvailabilitySnapshot kTestFeatureAvailabilityAllEnabled =
    FeatureAvailabilitySnapshot(
      isWindows: true,
      majorVersion: 10,
      minorVersion: 0,
      isServerLikely: false,
      serverDetectionReliable: true,
      isInteractiveSessionLikely: true,
      interactiveDetectionReliable: true,
      osVersionParseFailed: false,
      webviewRuntimeAvailable: true,
      webviewProbeTimedOut: false,
      autoUpdateEnabled: true,
      windowManagementEnabled: true,
      trayEnabled: true,
      taskSchedulerEnabled: true,
      windowsServiceManagementEnabled: true,
      startupAtLogonTaskEnabled: true,
      externalBrowserOAuthEnabled: true,
      embeddedWebviewOAuthEnabled: true,
    );

void registerTestFeatureAvailability() {
  if (getIt.isRegistered<FeatureAvailabilityService>()) {
    getIt.unregister<FeatureAvailabilityService>();
  }
  getIt.registerSingleton<FeatureAvailabilityService>(
    FeatureAvailabilityService(kTestFeatureAvailabilityAllEnabled),
  );
}

void unregisterTestFeatureAvailability() {
  if (getIt.isRegistered<FeatureAvailabilityService>()) {
    getIt.unregister<FeatureAvailabilityService>();
  }
}
