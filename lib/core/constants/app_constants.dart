class AppConstants {
  // Timeouts
  static const Duration ftpTimeout = Duration(minutes: 10);
  static const Duration httpTimeout = Duration(minutes: 5);
  static const Duration processTimeout = Duration(hours: 2);

  // Retry
  static const Duration retryDelay = Duration(seconds: 5);
  static const int maxRetries = 3;

  // Google Drive
  static const List<String> googleDriveScopes = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/userinfo.email',
  ];

  // Dropbox
  static const List<String> dropboxScopes = [
    'files.content.write',
    'files.content.read',
    'account_info.read',
  ];
  static const String dropboxApiBaseUrl = 'https://api.dropboxapi.com';
  static const String dropboxContentBaseUrl = 'https://content.dropboxapi.com';
  static const int dropboxSimpleUploadLimit = 150 * 1024 * 1024; // 150MB

  // OAuth2 Loopback Server
  static const int oauthLoopbackPort = 8085;
  static const String oauthRedirectUri = 'http://localhost:8085/oauth2redirect';

  // Backup
  static const int defaultRetentionDays = 30;
  static const int minBackupSizeBytes = 1024; // 1KB

  // FTP
  static const int defaultFtpPort = 21;
  static const int defaultFtpsPort = 990;

  // Sybase
  static const int defaultSybasePort = 2638;

  // Logs
  static const int logRotationDays = 90;
}
