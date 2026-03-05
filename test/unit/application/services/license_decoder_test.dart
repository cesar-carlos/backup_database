import 'dart:convert';
import 'dart:typed_data';

import 'package:backup_database/application/services/license_decoder.dart';
import 'package:backup_database/application/services/license_generation_service.dart';
import 'package:backup_database/core/constants/license_constants.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LicenseDecoder v2-only (Ed25519)', () {
    late ed.KeyPair keyPair;
    late LicenseDecoder decoder;
    late LicenseGenerationService generationService;

    setUp(() {
      keyPair = ed.generateKey();
      decoder = LicenseDecoder(publicKeyBytes: keyPair.publicKey.bytes);
      generationService = LicenseGenerationService(
        privateKeyBytes: keyPair.privateKey.bytes,
        licenseDecoder: decoder,
      );
    });

    test('rejects empty license key', () async {
      final result = await decoder.decode('');
      expect(result.isError(), isTrue);
    });

    test('rejects invalid base64', () async {
      final result = await decoder.decode('not-valid-base64!!!');
      expect(result.isError(), isTrue);
    });

    test('decodes valid v2 license from generation service', () async {
      final genResult = await generationService.generateLicenseKey(
        deviceKey: 'device-v2',
        allowedFeatures: const ['remote_control', 'email_notification'],
        expiresAt: DateTime.now().add(const Duration(days: 90)),
      );

      expect(genResult.isSuccess(), isTrue);
      final licenseKey = genResult.getOrNull()!;

      final result = await decoder.decode(licenseKey);

      expect(result.isSuccess(), isTrue);
      final data = result.getOrNull()!;
      expect(data['deviceKey'], 'device-v2');
      expect(data['allowedFeatures'], ['remote_control', 'email_notification']);
      expect(data['expiresAt'], isNotNull);
    });

    test('rejects v2 license with invalid signature', () async {
      final genResult = await generationService.generateLicenseKey(
        deviceKey: 'device-v2',
        allowedFeatures: const ['f1'],
      );
      final licenseKey = genResult.getOrNull()!;

      final licenseBytes = base64.decode(licenseKey);
      final licenseJson = utf8.decode(licenseBytes);
      final licenseData = jsonDecode(licenseJson) as Map<String, dynamic>;
      (licenseData['data'] as Map<String, dynamic>)['deviceKey'] = 'tampered';
      licenseData['signature'] = base64.encode(List.filled(64, 0));

      final tamperedKey = base64.encode(utf8.encode(jsonEncode(licenseData)));

      final result = await decoder.decode(tamperedKey);

      expect(result.isError(), isTrue);
    });

    test('rejects v2 license when notBefore is in future', () async {
      final now = DateTime.now();
      final notBefore = now.add(const Duration(days: 1));

      final genResult = await generationService.generateLicenseKey(
        deviceKey: 'device-v2',
        allowedFeatures: const ['f1'],
        notBefore: notBefore,
      );
      final licenseKey = genResult.getOrNull()!;

      final result = await decoder.decode(licenseKey);

      expect(result.isError(), isTrue);
    });

    test('rejects v2 license when expiresAt is in past', () async {
      final now = DateTime.now();
      final expiresAt = now.subtract(const Duration(days: 1));

      final genResult = await generationService.generateLicenseKey(
        deviceKey: 'device-v2',
        allowedFeatures: const ['f1'],
        expiresAt: expiresAt,
      );
      final licenseKey = genResult.getOrNull()!;

      final result = await decoder.decode(licenseKey);

      expect(result.isError(), isTrue);
    });

    test('rejects license with missing required fields', () async {
      final data = <String, dynamic>{
        'licenseVersion': LicenseConstants.currentVersion,
        'deviceKey': 'device-v2',
      };

      final dataJson = jsonEncode(data);
      final messageBytes = utf8.encode(dataJson);
      final sig = ed.sign(
        keyPair.privateKey,
        Uint8List.fromList(messageBytes),
      );

      final licenseData = {
        'data': data,
        'signature': base64.encode(sig),
      };
      final licenseKey = base64.encode(utf8.encode(jsonEncode(licenseData)));

      final result = await decoder.decode(licenseKey);

      expect(result.isError(), isTrue);
    });

    test('rejects v1 license (unsupported version)', () async {
      final data = <String, dynamic>{
        'licenseVersion': 1,
        'deviceKey': 'device-v1',
        'allowedFeatures': ['f1'],
        'issuedAt': DateTime.now().toIso8601String(),
        'keyId': 'test-key',
        'issuer': LicenseConstants.issuerDefault,
      };

      final dataJson = jsonEncode(data);
      final messageBytes = utf8.encode(dataJson);
      final sig = ed.sign(
        keyPair.privateKey,
        Uint8List.fromList(messageBytes),
      );

      final licenseData = {
        'data': data,
        'signature': base64.encode(sig),
      };
      final licenseKey = base64.encode(utf8.encode(jsonEncode(licenseData)));

      final result = await decoder.decode(licenseKey);

      expect(result.isError(), isTrue);
    });

    test('rejects license with wrong issuer', () async {
      final data = <String, dynamic>{
        'licenseVersion': LicenseConstants.currentVersion,
        'deviceKey': 'device-v2',
        'allowedFeatures': ['f1'],
        'issuedAt': DateTime.now().toIso8601String(),
        'keyId': LicenseConstants.keyIdDefault,
        'issuer': 'wrong_issuer',
      };

      final dataJson = jsonEncode(data);
      final messageBytes = utf8.encode(dataJson);
      final sig = ed.sign(
        keyPair.privateKey,
        Uint8List.fromList(messageBytes),
      );

      final licenseData = {
        'data': data,
        'signature': base64.encode(sig),
      };
      final licenseKey = base64.encode(utf8.encode(jsonEncode(licenseData)));

      final result = await decoder.decode(licenseKey);

      expect(result.isError(), isTrue);
    });

    test('rejects license with wrong keyId', () async {
      final data = <String, dynamic>{
        'licenseVersion': LicenseConstants.currentVersion,
        'deviceKey': 'device-v2',
        'allowedFeatures': ['f1'],
        'issuedAt': DateTime.now().toIso8601String(),
        'keyId': 'unexpected-key',
        'issuer': LicenseConstants.issuerDefault,
      };

      final dataJson = jsonEncode(data);
      final messageBytes = utf8.encode(dataJson);
      final sig = ed.sign(
        keyPair.privateKey,
        Uint8List.fromList(messageBytes),
      );

      final licenseData = {
        'data': data,
        'signature': base64.encode(sig),
      };
      final licenseKey = base64.encode(utf8.encode(jsonEncode(licenseData)));

      final result = await decoder.decode(licenseKey);

      expect(result.isError(), isTrue);
    });

    test('rejects license with non-string feature values', () async {
      final data = <String, dynamic>{
        'licenseVersion': LicenseConstants.currentVersion,
        'deviceKey': 'device-v2',
        'allowedFeatures': ['f1', 1, true],
        'issuedAt': DateTime.now().toIso8601String(),
        'keyId': LicenseConstants.keyIdDefault,
        'issuer': LicenseConstants.issuerDefault,
      };

      final dataJson = jsonEncode(data);
      final messageBytes = utf8.encode(dataJson);
      final sig = ed.sign(
        keyPair.privateKey,
        Uint8List.fromList(messageBytes),
      );

      final licenseData = {
        'data': data,
        'signature': base64.encode(sig),
      };
      final licenseKey = base64.encode(utf8.encode(jsonEncode(licenseData)));

      final result = await decoder.decode(licenseKey);

      expect(result.isError(), isTrue);
    });
  });

  group('LicenseGenerationService.createLicenseFromKey', () {
    late ed.KeyPair keyPair;
    late LicenseDecoder decoder;
    late LicenseGenerationService generationService;

    setUp(() {
      keyPair = ed.generateKey();
      decoder = LicenseDecoder(publicKeyBytes: keyPair.publicKey.bytes);
      generationService = LicenseGenerationService(
        privateKeyBytes: keyPair.privateKey.bytes,
        licenseDecoder: decoder,
      );
    });

    test('creates license entity from valid key', () async {
      final genResult = await generationService.generateLicenseKey(
        deviceKey: 'device-compat',
        allowedFeatures: const ['email_notification'],
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      final licenseKey = genResult.getOrNull()!;

      final createResult = await generationService.createLicenseFromKey(
        licenseKey: licenseKey,
        deviceKey: 'device-compat',
      );

      expect(createResult.isSuccess(), isTrue);
      final license = createResult.getOrNull()!;
      expect(license.deviceKey, 'device-compat');
      expect(license.hasFeature('email_notification'), isTrue);
    });

    test('rejects license for wrong device', () async {
      final genResult = await generationService.generateLicenseKey(
        deviceKey: 'device-a',
        allowedFeatures: const ['f1'],
      );
      final licenseKey = genResult.getOrNull()!;

      final createResult = await generationService.createLicenseFromKey(
        licenseKey: licenseKey,
        deviceKey: 'device-b',
      );

      expect(createResult.isError(), isTrue);
    });

    test('disables local generation when private key is unavailable', () async {
      final generationServiceWithoutPrivateKey = LicenseGenerationService(
        licenseDecoder: decoder,
      );

      expect(generationServiceWithoutPrivateKey.canGenerateLocally, isFalse);

      final generateResult = await generationServiceWithoutPrivateKey
          .generateLicenseKey(
            deviceKey: 'device-a',
            allowedFeatures: const ['f1'],
          );

      expect(generateResult.isError(), isTrue);
    });
  });
}
