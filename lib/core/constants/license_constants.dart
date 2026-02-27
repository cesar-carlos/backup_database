class LicenseConstants {
  static const int version1 = 1;
  static const int version2 = 2;

  static const String issuerDefault = 'backup_database';
  static const String keyIdDefault = 'ed25519-1';

  static const String envLicensePublicKey = 'BACKUP_DATABASE_LICENSE_PUBLIC_KEY';

  static const String envRevocationList = 'BACKUP_DATABASE_LICENSE_REVOCATION_LIST';
  static const String envRevocationListPath =
      'BACKUP_DATABASE_LICENSE_REVOCATION_LIST_PATH';
}
