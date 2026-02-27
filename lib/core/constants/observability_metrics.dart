class ObservabilityMetrics {
  ObservabilityMetrics._();

  static const licenseDeniedTotal = 'license_denied_total';
  static const scheduleUpdateRejectedTotal = 'schedule_update_rejected_total';
  static const backupRunDurationMs = 'backup_run_duration_ms';
  static const destinationUploadDurationMs = 'destination_upload_duration_ms';
  static const destinationUploadFailureTotal = 'destination_upload_failure_total';
  static const emailNotificationSkippedLicenseTotal =
      'email_notification_skipped_license_total';

  static const windowsServiceInstallSuccess = 'windows_service_install_success';
  static const windowsServiceInstallFailure = 'windows_service_install_failure';
  static const windowsServiceStartSuccess = 'windows_service_start_success';
  static const windowsServiceStartFailure = 'windows_service_start_failure';
  static const windowsServiceStartConvergenceSeconds =
      'windows_service_start_convergence_seconds';
  static const windowsServiceStopSuccess = 'windows_service_stop_success';
  static const windowsServiceStopFailure = 'windows_service_stop_failure';
  static const windowsServiceStopConvergenceSeconds =
      'windows_service_stop_convergence_seconds';
  static const windowsServiceRestartSuccess = 'windows_service_restart_success';
  static const windowsServiceRestartFailure = 'windows_service_restart_failure';
  static const windowsServiceUninstallSuccess =
      'windows_service_uninstall_success';
  static const windowsServiceUninstallFailure =
      'windows_service_uninstall_failure';
  static const windowsServiceScRetries = 'windows_service_sc_retries';
}
