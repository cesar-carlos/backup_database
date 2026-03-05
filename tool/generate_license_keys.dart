import 'dart:convert';
import 'dart:io';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

void main() {
  final keyPair = ed.generateKey();
  final publicKeyBase64 = base64.encode(keyPair.publicKey.bytes);
  final privateKeyBase64 = base64.encode(keyPair.privateKey.bytes);

  stdout.writeln('PUBLIC_B64=$publicKeyBase64');
  stdout.writeln('PRIVATE_B64=$privateKeyBase64');
  stdout.writeln('PUBLIC_LEN=${keyPair.publicKey.bytes.length}');
  stdout.writeln('PRIVATE_LEN=${keyPair.privateKey.bytes.length}');
}
