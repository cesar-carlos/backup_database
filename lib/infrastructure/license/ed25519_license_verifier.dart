import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

const _ed25519PublicKeySize = 32;
const _ed25519SignatureSize = 64;

class Ed25519LicenseVerifier {
  Ed25519LicenseVerifier({required List<int> publicKeyBytes})
    : _publicKey = ed.PublicKey(publicKeyBytes);

  final ed.PublicKey _publicKey;

  bool verify({
    required List<int> messageBytes,
    required List<int> signatureBytes,
  }) {
    if (_publicKey.bytes.length != _ed25519PublicKeySize) {
      return false;
    }
    if (signatureBytes.length != _ed25519SignatureSize) {
      return false;
    }
    return ed.verify(
      _publicKey,
      Uint8List.fromList(messageBytes),
      Uint8List.fromList(signatureBytes),
    );
  }
}
