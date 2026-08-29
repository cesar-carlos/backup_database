import 'package:backup_database/application/services/license_decoder.dart';
import 'package:backup_database/infrastructure/license/ed25519_license_verifier.dart';
import 'package:backup_database/infrastructure/license/license_public_keys.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LicenseDecoderFactory {
  LicenseDecoderFactory._();

  static rd.Result<LicenseDecoder> fromEnv() {
    final keysResult = LicensePublicKeys.fromEnv();
    return keysResult.fold(
      (keys) => rd.Success(
        LicenseDecoder(
          verifiers: {
            for (final entry in keys.entries)
              entry.key: Ed25519LicenseVerifier(publicKeyBytes: entry.value),
          },
        ),
      ),
      rd.Failure.new,
    );
  }
}
