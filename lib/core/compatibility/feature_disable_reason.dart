enum FeatureDisableReason {
  notWindows,
  osVersionUnresolved,
  osBelowMinimum,
  autoUpdateUnsupportedLegacyServer,
  oauthExternalUnsupportedOs,
  webviewRuntimeUnavailable,
  webviewProbeTimedOut,
  embeddedWebviewUnsupportedLegacyServer,
  nonInteractiveSession,
  trayRequiresInteractiveSession,
  windowManagementRequiresInteractiveSession,
}

extension FeatureDisableReasonDiagnostic on FeatureDisableReason {
  String get diagnosticLabel {
    switch (this) {
      case FeatureDisableReason.notWindows:
        return 'not_windows';
      case FeatureDisableReason.osVersionUnresolved:
        return 'os_version_unresolved';
      case FeatureDisableReason.osBelowMinimum:
        return 'os_below_minimum';
      case FeatureDisableReason.autoUpdateUnsupportedLegacyServer:
        return 'auto_update_legacy_server';
      case FeatureDisableReason.oauthExternalUnsupportedOs:
        return 'oauth_external_unsupported_os';
      case FeatureDisableReason.webviewRuntimeUnavailable:
        return 'webview_runtime_unavailable';
      case FeatureDisableReason.webviewProbeTimedOut:
        return 'webview_probe_timed_out';
      case FeatureDisableReason.embeddedWebviewUnsupportedLegacyServer:
        return 'embedded_webview_legacy_server';
      case FeatureDisableReason.nonInteractiveSession:
        return 'non_interactive_session';
      case FeatureDisableReason.trayRequiresInteractiveSession:
        return 'tray_requires_interactive_session';
      case FeatureDisableReason.windowManagementRequiresInteractiveSession:
        return 'window_management_requires_interactive_session';
    }
  }
}
