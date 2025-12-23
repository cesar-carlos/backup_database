class LicenseFeatures {
  static const String differentialBackup = 'differential_backup';
  static const String logBackup = 'log_backup';
  static const String intervalSchedule = 'interval_schedule';
  static const String googleDrive = 'google_drive';
  static const String dropbox = 'dropbox';
  static const String verifyIntegrity = 'verify_integrity';
  static const String postBackupScript = 'post_backup_script';
  static const String emailNotification = 'email_notification';

  static const List<String> allFeatures = [
    differentialBackup,
    logBackup,
    intervalSchedule,
    googleDrive,
    dropbox,
    verifyIntegrity,
    postBackupScript,
    emailNotification,
  ];
}

