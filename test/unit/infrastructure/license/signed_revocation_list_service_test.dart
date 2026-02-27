import 'dart:convert';
import 'dart:typed_data';

import 'package:backup_database/infrastructure/license/signed_revocation_list_service.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SignedRevocationListService', () {
    test('isRevoked returns false when no list configured', () async {
      final service = SignedRevocationListService();
      final revoked = await service.isRevoked('any-device-key');
      expect(revoked, isFalse);
    });

    test('isRevoked returns false for non-revoked key when list is empty', () async {
      final keyPair = ed.generateKey();
      final data = {
        'revokedDeviceKeys': <String>[],
        'issuedAt': DateTime.now().toIso8601String(),
      };
      final dataJson = jsonEncode(data);
      final messageBytes = Uint8List.fromList(utf8.encode(dataJson));
      final sig = ed.sign(
        keyPair.privateKey,
        messageBytes,
      );
      final listJson = jsonEncode({
        'data': data,
        'signature': base64.encode(sig),
      });

      final service = SignedRevocationListService.forTesting(
        publicKeyBytes: keyPair.publicKey.bytes,
        revocationListJson: listJson,
      );

      final revoked = await service.isRevoked('device-1');
      expect(revoked, isFalse);
    });

    test('isRevoked returns true for revoked key', () async {
      final keyPair = ed.generateKey();
      const revokedKey = 'revoked-device-123';
      final data = {
        'revokedDeviceKeys': [revokedKey],
        'issuedAt': DateTime.now().toIso8601String(),
      };
      final dataJson = jsonEncode(data);
      final messageBytes = Uint8List.fromList(utf8.encode(dataJson));
      final sig = ed.sign(
        keyPair.privateKey,
        messageBytes,
      );
      final listJson = jsonEncode({
        'data': data,
        'signature': base64.encode(sig),
      });

      final service = SignedRevocationListService.forTesting(
        publicKeyBytes: keyPair.publicKey.bytes,
        revocationListJson: listJson,
      );

      expect(await service.isRevoked(revokedKey), isTrue);
      expect(await service.isRevoked('other-device'), isFalse);
    });

    test('rejects list with invalid signature', () async {
      final keyPair = ed.generateKey();
      final data = {
        'revokedDeviceKeys': ['device-1'],
        'issuedAt': DateTime.now().toIso8601String(),
      };
      final listJson = jsonEncode({
        'data': data,
        'signature': base64.encode(List.filled(64, 0)),
      });

      final service = SignedRevocationListService.forTesting(
        publicKeyBytes: keyPair.publicKey.bytes,
        revocationListJson: listJson,
      );

      final revoked = await service.isRevoked('device-1');
      expect(revoked, isFalse);
    });
  });
}
