import 'dart:typed_data';

import 'package:backup_database/infrastructure/security/credential_machine_blob_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('credential_machine_blob_codec', () {
    test('roundtrip preserves key and value', () {
      const key = 'sql_server_password_abc';
      const value = 'p@ss&word<>';
      final encoded = encodeCredentialMachineBlob(
        logicalKey: key,
        valueUtf8: value,
      );
      final decoded = decodeCredentialMachineBlob(encoded);
      expect(decoded.key, key);
      expect(decoded.value, value);
    });

    test('decode rejects wrong version', () {
      final bad = Uint8List.fromList([0x02, 0, 0, 0, 1, 0x61]);
      expect(
        () => decodeCredentialMachineBlob(bad),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
