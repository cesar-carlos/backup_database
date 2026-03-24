import 'dart:convert';
import 'dart:typed_data';

const int credentialMachineBlobVersion = 0x01;

Uint8List encodeCredentialMachineBlob({
  required String logicalKey,
  required String valueUtf8,
}) {
  final keyBytes = utf8.encode(logicalKey);
  final valueBytes = utf8.encode(valueUtf8);
  if (keyBytes.length > 0xffff) {
    throw ArgumentError.value(logicalKey, 'logicalKey', 'key too long');
  }
  final builder = BytesBuilder(copy: false);
  builder.addByte(credentialMachineBlobVersion);
  final len = keyBytes.length;
  builder.add(<int>[
    (len >> 24) & 0xff,
    (len >> 16) & 0xff,
    (len >> 8) & 0xff,
    len & 0xff,
  ]);
  builder.add(keyBytes);
  builder.add(valueBytes);
  return builder.toBytes();
}

({String key, String value}) decodeCredentialMachineBlob(Uint8List plain) {
  if (plain.length < 5) {
    throw const FormatException('blob too short');
  }
  if (plain[0] != credentialMachineBlobVersion) {
    throw FormatException('unsupported blob version ${plain[0]}');
  }
  final keyLen = ByteData.sublistView(plain, 1, 5).getUint32(0);
  final keyEnd = 5 + keyLen;
  if (keyEnd > plain.length) {
    throw const FormatException('invalid key length');
  }
  final key = utf8.decode(plain.sublist(5, keyEnd));
  final value = utf8.decode(plain.sublist(keyEnd));
  return (key: key, value: value);
}
