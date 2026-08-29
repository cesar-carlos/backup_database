import 'package:backup_database/application/services/license_decoder.dart';
import 'package:backup_database/infrastructure/license/ed25519_license_verifier.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'DIP: decoder is wired with LicenseSignatureVerifier, not infra types',
    () {
      final keyPair = ed.generateKey();
      final decoder = LicenseDecoder(
        verifiers: {
          'ed25519-1': Ed25519LicenseVerifier(
            publicKeyBytes: keyPair.publicKey.bytes,
          ),
        },
      );
      expect(decoder.isAvailable, isTrue);
      expect(decoder.acceptedKeyIds, ['ed25519-1']);
    },
  );
}
