class SecureCredentialKeys {
  SecureCredentialKeys._();

  static const String sqlServerPasswordPrefix = 'sql_server_password_';
  static const String sybasePasswordPrefix = 'sybase_password_';
  static const String postgresPasswordPrefix = 'postgres_password_';
  static const String firebirdPasswordPrefix = 'firebird_password_';

  static String sqlServerPasswordKey(String id) =>
      '$sqlServerPasswordPrefix$id';

  static String sybasePasswordKey(String id) => '$sybasePasswordPrefix$id';

  static String postgresPasswordKey(String id) => '$postgresPasswordPrefix$id';

  static String firebirdPasswordKey(String id) => '$firebirdPasswordPrefix$id';
}
