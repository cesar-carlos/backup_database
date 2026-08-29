class LicenseTrialConstants {
  LicenseTrialConstants._();

  /// Fim exclusivo da avaliação full/free: 2027-10-02 00:00:00-03:00
  /// (01/10/2027 incluso em America/Sao_Paulo, UTC-3 o ano todo).
  static final DateTime trialEndsExclusive = DateTime.utc(2027, 10, 2, 3);

  static const Duration trialReminderLead = Duration(days: 30);

  static const String trialLicenseKey = 'trial:full-free';
  static const String trialLicenseId = 'trial';

  static const String envForceEnded = 'LICENSE_TRIAL_FORCE_ENDED';
  static const String envEndsAt = 'LICENSE_TRIAL_ENDS_AT';
}
