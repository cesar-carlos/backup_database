class LicenseConstants {
  static const int currentVersion = 2;

  static const String issuerDefault = 'backup_database';

  /// `keyId` da chave **legada** (primeira geração).
  ///
  /// Mantido como default para compatibilidade com licenças já emitidas
  /// e como `activeKeyId` quando `BACKUP_DATABASE_LICENSE_ACTIVE_KEY_ID`
  /// não é configurado. Para introduzir uma chave nova (rotação), use
  /// `BACKUP_DATABASE_LICENSE_PUBLIC_KEYS` (mapa JSON keyId → base64).
  static const String keyIdDefault = 'ed25519-1';

  /// Public key única (legacy). Continua aceita para compatibilidade
  /// e é tratada implicitamente como `keyIdDefault`.
  static const String envLicensePublicKey =
      'BACKUP_DATABASE_LICENSE_PUBLIC_KEY';

  /// Mapa JSON `{"ed25519-1": "base64", "ed25519-2": "base64"}` com as
  /// public keys aceitas para **verificação**. Permite manter a chave
  /// antiga válida durante o período de rotação enquanto licenças com
  /// a chave nova são emitidas em paralelo.
  static const String envLicensePublicKeys =
      'BACKUP_DATABASE_LICENSE_PUBLIC_KEYS';

  /// Chave privada da chave **ativa** (usada por `generateLicenseKey`).
  /// 64 bytes base64. APENAS em ambiente dev/admin — nunca no asset
  /// bundled (ver `EnvironmentLoader.forbiddenInBundledAssetKeys`).
  static const String envLicensePrivateKey =
      'BACKUP_DATABASE_LICENSE_PRIVATE_KEY';

  /// `keyId` que `generateLicenseKey` usa para assinar **novas**
  /// licenças. Default: [keyIdDefault]. Configure como `ed25519-2` (ou
  /// qualquer string) quando estiver emitindo licenças com a chave
  /// rotacionada.
  static const String envLicenseActiveKeyId =
      'BACKUP_DATABASE_LICENSE_ACTIVE_KEY_ID';

  static const String envRevocationList =
      'BACKUP_DATABASE_LICENSE_REVOCATION_LIST';
  static const String envRevocationListPath =
      'BACKUP_DATABASE_LICENSE_REVOCATION_LIST_PATH';

  static const Duration revocationListTtl = Duration(minutes: 15);
}
