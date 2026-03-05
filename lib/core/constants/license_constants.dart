class LicenseConstants {
  static const int currentVersion = 2;

  static const String issuerDefault = 'backup_database';
  static const String keyIdDefault = 'ed25519-1';

  static const String envLicensePublicKey =
      'BACKUP_DATABASE_LICENSE_PUBLIC_KEY';
  static const String envLicensePrivateKey =
      'BACKUP_DATABASE_LICENSE_PRIVATE_KEY';

  static const String envRevocationList =
      'BACKUP_DATABASE_LICENSE_REVOCATION_LIST';
  static const String envRevocationListPath =
      'BACKUP_DATABASE_LICENSE_REVOCATION_LIST_PATH';

  static const Duration revocationListTtl = Duration(minutes: 15);
}
