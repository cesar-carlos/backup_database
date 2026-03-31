import 'package:backup_database/core/compatibility/feature_disable_reason.dart';
import 'package:backup_database/core/compatibility/windows_compatibility_policy.dart';
import 'package:flutter_test/flutter_test.dart';

class _PolicyCase {
  const _PolicyCase({
    required this.name,
    required this.majorVersion,
    required this.minorVersion,
    required this.isServerLikely,
    required this.serverDetectionReliable,
    required this.isInteractiveSessionLikely,
    required this.interactiveDetectionReliable,
    required this.webviewRuntimeAvailable,
    required this.webviewProbeTimedOut,
    required this.osVersionParseFailed,
    required this.expectAutoUpdateEnabled,
    required this.expectWindowManagementEnabled,
    required this.expectTrayEnabled,
    required this.expectTaskSchedulerEnabled,
    required this.expectWindowsServiceManagementEnabled,
    required this.expectStartupAtLogonTaskEnabled,
    required this.expectExternalOAuthEnabled,
    required this.expectEmbeddedOAuthEnabled,
    this.expectAutoUpdateReason,
    this.expectWindowManagementReason,
    this.expectTrayReason,
    this.expectTaskSchedulerReason,
    this.expectWindowsServiceReason,
    this.expectStartupTaskReason,
    this.expectExternalOAuthReason,
    this.expectEmbeddedOAuthReason,
  });

  final String name;
  final int majorVersion;
  final int minorVersion;
  final bool isServerLikely;
  final bool serverDetectionReliable;
  final bool isInteractiveSessionLikely;
  final bool interactiveDetectionReliable;
  final bool webviewRuntimeAvailable;
  final bool webviewProbeTimedOut;
  final bool osVersionParseFailed;

  final bool expectAutoUpdateEnabled;
  final bool expectWindowManagementEnabled;
  final bool expectTrayEnabled;
  final bool expectTaskSchedulerEnabled;
  final bool expectWindowsServiceManagementEnabled;
  final bool expectStartupAtLogonTaskEnabled;
  final bool expectExternalOAuthEnabled;
  final bool expectEmbeddedOAuthEnabled;

  final FeatureDisableReason? expectAutoUpdateReason;
  final FeatureDisableReason? expectWindowManagementReason;
  final FeatureDisableReason? expectTrayReason;
  final FeatureDisableReason? expectTaskSchedulerReason;
  final FeatureDisableReason? expectWindowsServiceReason;
  final FeatureDisableReason? expectStartupTaskReason;
  final FeatureDisableReason? expectExternalOAuthReason;
  final FeatureDisableReason? expectEmbeddedOAuthReason;
}

void main() {
  group('WindowsCompatibilityPolicy', () {
    test('conservativeFallback is safe when OS parse fails', () {
      final snapshot = WindowsCompatibilityPolicy.conservativeFallback(
        webviewRuntimeAvailable: false,
        webviewProbeTimedOut: false,
      );

      expect(snapshot.autoUpdateEnabled, isFalse);
      expect(snapshot.taskSchedulerEnabled, isFalse);
      expect(snapshot.windowsServiceManagementEnabled, isFalse);
      expect(snapshot.externalBrowserOAuthEnabled, isFalse);
      expect(snapshot.embeddedWebviewOAuthEnabled, isFalse);
      expect(snapshot.osVersionParseFailed, isTrue);
      expect(
        snapshot.taskSchedulerDisabledReason,
        FeatureDisableReason.osVersionUnresolved,
      );
      expect(
        snapshot.windowsServiceManagementDisabledReason,
        FeatureDisableReason.osVersionUnresolved,
      );
      expect(
        snapshot.windowManagementDisabledReason,
        FeatureDisableReason.osVersionUnresolved,
      );
      expect(
        snapshot.trayDisabledReason,
        FeatureDisableReason.osVersionUnresolved,
      );
    });

    const cases = <_PolicyCase>[
      _PolicyCase(
        name: 'Windows 8 desktop interactive enables core + UI features',
        majorVersion: 6,
        minorVersion: 2,
        isServerLikely: false,
        serverDetectionReliable: true,
        isInteractiveSessionLikely: true,
        interactiveDetectionReliable: true,
        webviewRuntimeAvailable: true,
        webviewProbeTimedOut: false,
        osVersionParseFailed: false,
        expectAutoUpdateEnabled: true,
        expectWindowManagementEnabled: true,
        expectTrayEnabled: true,
        expectTaskSchedulerEnabled: true,
        expectWindowsServiceManagementEnabled: true,
        expectStartupAtLogonTaskEnabled: true,
        expectExternalOAuthEnabled: true,
        expectEmbeddedOAuthEnabled: true,
      ),
      _PolicyCase(
        name:
            'Server 2012 keeps core features but disables auto-update '
            'and embedded OAuth',
        majorVersion: 6,
        minorVersion: 2,
        isServerLikely: true,
        serverDetectionReliable: true,
        isInteractiveSessionLikely: true,
        interactiveDetectionReliable: true,
        webviewRuntimeAvailable: true,
        webviewProbeTimedOut: false,
        osVersionParseFailed: false,
        expectAutoUpdateEnabled: false,
        expectWindowManagementEnabled: true,
        expectTrayEnabled: true,
        expectTaskSchedulerEnabled: true,
        expectWindowsServiceManagementEnabled: true,
        expectStartupAtLogonTaskEnabled: true,
        expectExternalOAuthEnabled: true,
        expectEmbeddedOAuthEnabled: false,
        expectAutoUpdateReason:
            FeatureDisableReason.autoUpdateUnsupportedLegacyServer,
        expectEmbeddedOAuthReason:
            FeatureDisableReason.embeddedWebviewUnsupportedLegacyServer,
      ),
      _PolicyCase(
        name: 'Non-interactive session disables tray and window management',
        majorVersion: 10,
        minorVersion: 0,
        isServerLikely: false,
        serverDetectionReliable: true,
        isInteractiveSessionLikely: false,
        interactiveDetectionReliable: true,
        webviewRuntimeAvailable: true,
        webviewProbeTimedOut: false,
        osVersionParseFailed: false,
        expectAutoUpdateEnabled: true,
        expectWindowManagementEnabled: false,
        expectTrayEnabled: false,
        expectTaskSchedulerEnabled: true,
        expectWindowsServiceManagementEnabled: true,
        expectStartupAtLogonTaskEnabled: true,
        expectExternalOAuthEnabled: true,
        expectEmbeddedOAuthEnabled: true,
        expectWindowManagementReason:
            FeatureDisableReason.windowManagementRequiresInteractiveSession,
        expectTrayReason: FeatureDisableReason.trayRequiresInteractiveSession,
      ),
      _PolicyCase(
        name: 'WebView timeout gives explicit reason for embedded OAuth',
        majorVersion: 10,
        minorVersion: 0,
        isServerLikely: false,
        serverDetectionReliable: true,
        isInteractiveSessionLikely: true,
        interactiveDetectionReliable: true,
        webviewRuntimeAvailable: false,
        webviewProbeTimedOut: true,
        osVersionParseFailed: false,
        expectAutoUpdateEnabled: true,
        expectWindowManagementEnabled: true,
        expectTrayEnabled: true,
        expectTaskSchedulerEnabled: true,
        expectWindowsServiceManagementEnabled: true,
        expectStartupAtLogonTaskEnabled: true,
        expectExternalOAuthEnabled: true,
        expectEmbeddedOAuthEnabled: false,
        expectEmbeddedOAuthReason: FeatureDisableReason.webviewProbeTimedOut,
      ),
      _PolicyCase(
        name: 'Windows 7 path disables everything with below-minimum reason',
        majorVersion: 6,
        minorVersion: 1,
        isServerLikely: false,
        serverDetectionReliable: true,
        isInteractiveSessionLikely: true,
        interactiveDetectionReliable: true,
        webviewRuntimeAvailable: true,
        webviewProbeTimedOut: false,
        osVersionParseFailed: false,
        expectAutoUpdateEnabled: false,
        expectWindowManagementEnabled: false,
        expectTrayEnabled: false,
        expectTaskSchedulerEnabled: false,
        expectWindowsServiceManagementEnabled: false,
        expectStartupAtLogonTaskEnabled: false,
        expectExternalOAuthEnabled: false,
        expectEmbeddedOAuthEnabled: false,
        expectAutoUpdateReason: FeatureDisableReason.osBelowMinimum,
        expectWindowManagementReason: FeatureDisableReason.osBelowMinimum,
        expectTrayReason: FeatureDisableReason.osBelowMinimum,
        expectTaskSchedulerReason: FeatureDisableReason.osBelowMinimum,
        expectWindowsServiceReason: FeatureDisableReason.osBelowMinimum,
        expectStartupTaskReason: FeatureDisableReason.osBelowMinimum,
        expectExternalOAuthReason: FeatureDisableReason.osBelowMinimum,
        expectEmbeddedOAuthReason: FeatureDisableReason.osBelowMinimum,
      ),
      _PolicyCase(
        name: 'Unknown OS version disables with unresolved-version reason',
        majorVersion: 10,
        minorVersion: 0,
        isServerLikely: false,
        serverDetectionReliable: false,
        isInteractiveSessionLikely: true,
        interactiveDetectionReliable: false,
        webviewRuntimeAvailable: true,
        webviewProbeTimedOut: false,
        osVersionParseFailed: true,
        expectAutoUpdateEnabled: false,
        expectWindowManagementEnabled: false,
        expectTrayEnabled: false,
        expectTaskSchedulerEnabled: false,
        expectWindowsServiceManagementEnabled: false,
        expectStartupAtLogonTaskEnabled: false,
        expectExternalOAuthEnabled: false,
        expectEmbeddedOAuthEnabled: false,
        expectAutoUpdateReason: FeatureDisableReason.osVersionUnresolved,
        expectWindowManagementReason: FeatureDisableReason.osVersionUnresolved,
        expectTrayReason: FeatureDisableReason.osVersionUnresolved,
        expectTaskSchedulerReason: FeatureDisableReason.osVersionUnresolved,
        expectWindowsServiceReason: FeatureDisableReason.osVersionUnresolved,
        expectStartupTaskReason: FeatureDisableReason.osVersionUnresolved,
        expectExternalOAuthReason: FeatureDisableReason.osVersionUnresolved,
        expectEmbeddedOAuthReason: FeatureDisableReason.osVersionUnresolved,
      ),
    ];

    for (final caseData in cases) {
      test(caseData.name, () {
        final snapshot = WindowsCompatibilityPolicy.compute(
          majorVersion: caseData.majorVersion,
          minorVersion: caseData.minorVersion,
          isServerLikely: caseData.isServerLikely,
          serverDetectionReliable: caseData.serverDetectionReliable,
          isInteractiveSessionLikely: caseData.isInteractiveSessionLikely,
          interactiveDetectionReliable: caseData.interactiveDetectionReliable,
          webviewRuntimeAvailable: caseData.webviewRuntimeAvailable,
          webviewProbeTimedOut: caseData.webviewProbeTimedOut,
          osVersionParseFailed: caseData.osVersionParseFailed,
        );

        expect(snapshot.autoUpdateEnabled, caseData.expectAutoUpdateEnabled);
        expect(
          snapshot.windowManagementEnabled,
          caseData.expectWindowManagementEnabled,
        );
        expect(snapshot.trayEnabled, caseData.expectTrayEnabled);
        expect(
          snapshot.taskSchedulerEnabled,
          caseData.expectTaskSchedulerEnabled,
        );
        expect(
          snapshot.windowsServiceManagementEnabled,
          caseData.expectWindowsServiceManagementEnabled,
        );
        expect(
          snapshot.startupAtLogonTaskEnabled,
          caseData.expectStartupAtLogonTaskEnabled,
        );
        expect(
          snapshot.externalBrowserOAuthEnabled,
          caseData.expectExternalOAuthEnabled,
        );
        expect(
          snapshot.embeddedWebviewOAuthEnabled,
          caseData.expectEmbeddedOAuthEnabled,
        );

        expect(
          snapshot.autoUpdateDisabledReason,
          caseData.expectAutoUpdateReason,
        );
        expect(
          snapshot.windowManagementDisabledReason,
          caseData.expectWindowManagementReason,
        );
        expect(snapshot.trayDisabledReason, caseData.expectTrayReason);
        expect(
          snapshot.taskSchedulerDisabledReason,
          caseData.expectTaskSchedulerReason,
        );
        expect(
          snapshot.windowsServiceManagementDisabledReason,
          caseData.expectWindowsServiceReason,
        );
        expect(
          snapshot.startupAtLogonTaskDisabledReason,
          caseData.expectStartupTaskReason,
        );
        expect(
          snapshot.externalBrowserOAuthDisabledReason,
          caseData.expectExternalOAuthReason,
        );
        expect(
          snapshot.embeddedWebviewDisabledReason,
          caseData.expectEmbeddedOAuthReason,
        );
      });
    }
  });
}
