class SecureCredentialKeys {
  SecureCredentialKeys._();

  static const String sqlServerPasswordPrefix = 'sql_server_password_';
  static const String sybasePasswordPrefix = 'sybase_password_';
  static const String postgresPasswordPrefix = 'postgres_password_';
  static const String firebirdPasswordPrefix = 'firebird_password_';
  static const String firebirdCryptKeyPrefix = 'firebird_crypt_key_';

  static String sqlServerPasswordKey(String id) =>
      '$sqlServerPasswordPrefix$id';

  static String sybasePasswordKey(String id) => '$sybasePasswordPrefix$id';

  static String postgresPasswordKey(String id) => '$postgresPasswordPrefix$id';

  static String firebirdPasswordKey(String id) => '$firebirdPasswordPrefix$id';

  /// Chave de criptografia AES do banco Firebird. Equipara o nivel de
  /// sensibilidade da senha do utilizador: nunca deve ficar em coluna
  /// texto puro do SQLite. Repositorio Firebird migra entradas
  /// pre-existentes (coluna `cryptKey`) na primeira leitura.
  static String firebirdCryptKeyKey(String id) =>
      '$firebirdCryptKeyPrefix$id';
}
