class AppConstants {
  static const Duration ftpTimeout = Duration(minutes: 60);
  static const Duration httpTimeout = Duration(minutes: 5);
  static const Duration processTimeout = Duration(hours: 2);

  static const Duration retryDelay = Duration(seconds: 5);
  static const int maxRetries = 3;

  static const List<String> googleDriveScopes = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/userinfo.email',
  ];

  static const List<String> dropboxScopes = [
    'files.content.write',
    'files.content.read',
    'account_info.read',
  ];
  static const String dropboxApiBaseUrl = 'https://api.dropboxapi.com';
  static const String dropboxContentBaseUrl = 'https://content.dropboxapi.com';
  static const int dropboxSimpleUploadLimit = 150 * 1024 * 1024;

  static const int oauthLoopbackPort = 8085;
  static const String oauthRedirectUri = 'http://localhost:8085/oauth2redirect';
  static const bool enableGoogleSmtpOAuth = bool.fromEnvironment(
    'ENABLE_GOOGLE_SMTP_OAUTH',
    defaultValue: true,
  );
  static const bool enableMicrosoftSmtpOAuth = bool.fromEnvironment(
    'ENABLE_MICROSOFT_SMTP_OAUTH',
    defaultValue: true,
  );
  static const String smtpGoogleClientId = String.fromEnvironment(
    'SMTP_GOOGLE_CLIENT_ID',
  );
  static const String smtpGoogleClientSecret = String.fromEnvironment(
    'SMTP_GOOGLE_CLIENT_SECRET',
  );
  static const String smtpMicrosoftClientId = String.fromEnvironment(
    'SMTP_MICROSOFT_CLIENT_ID',
  );
  static const String smtpMicrosoftClientSecret = String.fromEnvironment(
    'SMTP_MICROSOFT_CLIENT_SECRET',
  );
  static const String smtpMicrosoftTenant = String.fromEnvironment(
    'SMTP_MICROSOFT_TENANT',
    defaultValue: 'common',
  );
  static const List<String> smtpGoogleScopes = [
    'https://mail.google.com/',
    'https://www.googleapis.com/auth/userinfo.email',
    'openid',
    'profile',
  ];
  static const List<String> smtpMicrosoftScopes = [
    'openid',
    'profile',
    'email',
    'offline_access',
    'User.Read',
    'https://outlook.office.com/SMTP.Send',
  ];

  static const int defaultRetentionDays = 30;
  static const int minBackupSizeBytes = 1024;

  static const int defaultFtpPort = 21;
  static const int defaultFtpsPort = 990;

  static const int defaultSybasePort = 2638;

  static const int logRotationDays = 90;

  static const String windowsServiceLogPath =
      r'C:\ProgramData\BackupDatabase\logs';

  static const bool allowInsecureSmtp = bool.fromEnvironment(
    'ALLOW_INSECURE_SMTP',
  );

  static const bool ftpResumableUpload = bool.fromEnvironment(
    'FTP_RESUMABLE_UPLOAD',
    defaultValue: true,
  );

  static const String receivedBackupsDefaultPathKey =
      'received_backups_default_path';

  static const String scheduleTransferDestinationsKey =
      'schedule_transfer_destinations';

  static const Duration smtpSendTimeout = Duration(seconds: 20);
  static const int smtpMaxSendAttempts = 3;
  static const int smtpBaseRetryDelayMs = 400;
  static const int smtpMaxRetryDelayMs = 3000;
  static const int smtpHistoryReloadDebounceMs = 300;
}
