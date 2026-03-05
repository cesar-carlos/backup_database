import 'dart:convert';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

void main() {
  final keyPair = ed.generateKey();
  final publicKeyBase64 = base64.encode(keyPair.publicKey.bytes);
  final privateKeyBase64 = base64.encode(keyPair.privateKey.bytes);

  print('PUBLIC_B64=$publicKeyBase64');
  print('PRIVATE_B64=$privateKeyBase64');
  print('PUBLIC_LEN=${keyPair.publicKey.bytes.length}');
  print('PRIVATE_LEN=${keyPair.privateKey.bytes.length}');
}
