import 'dart:convert';
import 'dart:typed_data';

import 'package:backup_database/application/services/license_decoder.dart';
import 'package:backup_database/application/services/license_generation_service.dart';
import 'package:backup_database/core/constants/license_constants.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const v1Secret = 'test-secret-key-v1';

  group('LicenseDecoder v1 (HMAC)', () {
    late LicenseDecoder decoder;
    late LicenseGenerationService generationService;

    setUp(() {
      decoder = LicenseDecoder(v1SecretKey: v1Secret);
      generationService = LicenseGenerationService(
        secretKey: v1Secret,
        licenseDecoder: decoder,
      );
    });

    test('decodes valid v1 license from generation service', () async {
      final genResult = await generationService.generateLicenseKey(
        deviceKey: 'device-a',
        allowedFeatures: const ['f1', 'f2'],
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );

      expect(genResult.isSuccess(), isTrue);
      final licenseKey = genResult.getOrNull()!;

      final decodeResult = await decoder.decode(licenseKey);

      expect(decodeResult.isSuccess(), isTrue);
      final data = decodeResult.getOrNull()!;
      expect(data['deviceKey'], 'device-a');
      expect(data['allowedFeatures'], ['f1', 'f2']);
      expect(data['expiresAt'], isNotNull);
    });

    test('rejects v1 license with invalid signature', () async {
      final genResult = await generationService.generateLicenseKey(
        deviceKey: 'device-a',
        allowedFeatures: const ['f1'],
      );
      final licenseKey = genResult.getOrNull()!;

      final licenseBytes = base64.decode(licenseKey);
      final licenseJson = utf8.decode(licenseBytes);
      final licenseData = jsonDecode(licenseJson) as Map<String, dynamic>;
      licenseData['signature'] = 'tampered-signature';

      final tamperedKey = base64.encode(utf8.encode(jsonEncode(licenseData)));

      final decodeResult = await decoder.decode(tamperedKey);

      expect(decodeResult.isError(), isTrue);
    });

    test('rejects empty license key', () async {
      final result = await decoder.decode('');
      expect(result.isError(), isTrue);
    });

    test('rejects invalid base64', () async {
      final result = await decoder.decode('not-valid-base64!!!');
      expect(result.isError(), isTrue);
    });
  });

  group('LicenseDecoder v2 (Ed25519)', () {
    late ed.KeyPair keyPair;
    late LicenseDecoder decoderWithPublicKey;

    setUp(() {
      keyPair = ed.generateKey();
      decoderWithPublicKey = LicenseDecoder(
        v1SecretKey: v1Secret,
        v2PublicKeyBytes: keyPair.publicKey.bytes,
      );
    });

    String createV2License({
      required String deviceKey,
      required List<String> allowedFeatures,
      DateTime? expiresAt,
      DateTime? notBefore,
      DateTime? issuedAt,
    }) {
      final data = <String, dynamic>{
        'licenseVersion': LicenseConstants.version2,
        'deviceKey': deviceKey,
        'allowedFeatures': allowedFeatures,
        'expiresAt': expiresAt?.toIso8601String(),
        'notBefore': notBefore?.toIso8601String(),
        'issuedAt': issuedAt?.toIso8601String(),
        'issuer': LicenseConstants.issuerDefault,
        'keyId': LicenseConstants.keyIdDefault,
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
      return base64.encode(utf8.encode(jsonEncode(licenseData)));
    }

    test('decodes valid v2 license', () async {
      final licenseKey = createV2License(
        deviceKey: 'device-v2',
        allowedFeatures: const ['remote_control', 'email_notification'],
        expiresAt: DateTime.now().add(const Duration(days: 90)),
      );

      final result = await decoderWithPublicKey.decode(licenseKey);

      expect(result.isSuccess(), isTrue);
      final data = result.getOrNull()!;
      expect(data['deviceKey'], 'device-v2');
      expect(data['allowedFeatures'], ['remote_control', 'email_notification']);
    });

    test('rejects v2 license with invalid signature', () async {
      final licenseKey = createV2License(
        deviceKey: 'device-v2',
        allowedFeatures: const ['f1'],
      );

      final licenseBytes = base64.decode(licenseKey);
      final licenseJson = utf8.decode(licenseBytes);
      final licenseData = jsonDecode(licenseJson) as Map<String, dynamic>;
      (licenseData['data'] as Map<String, dynamic>)['deviceKey'] = 'tampered';
      licenseData['signature'] = base64.encode(List.filled(64, 0));

      final tamperedKey = base64.encode(utf8.encode(jsonEncode(licenseData)));

      final result = await decoderWithPublicKey.decode(tamperedKey);

      expect(result.isError(), isTrue);
    });

    test('rejects v2 license when notBefore is in future', () async {
      final licenseKey = createV2License(
        deviceKey: 'device-v2',
        allowedFeatures: const ['f1'],
        notBefore: DateTime.now().add(const Duration(days: 1)),
      );

      final result = await decoderWithPublicKey.decode(licenseKey);

      expect(result.isError(), isTrue);
    });

    test('returns failure when v2 license received but public key not configured',
        () async {
      final decoderWithoutKey = LicenseDecoder(v1SecretKey: v1Secret);
      final licenseKey = createV2License(
        deviceKey: 'device-v2',
        allowedFeatures: const ['f1'],
      );

      final result = await decoderWithoutKey.decode(licenseKey);

      expect(result.isError(), isTrue);
    });
  });

  group('LicenseDecoder v1/v2 compatibility', () {
    late LicenseDecoder decoder;
    late LicenseGenerationService generationService;

    setUp(() {
      decoder = LicenseDecoder(v1SecretKey: v1Secret);
      generationService = LicenseGenerationService(
        secretKey: v1Secret,
        licenseDecoder: decoder,
      );
    });

    test('createLicenseFromKey works with v1 license', () async {
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

    test('createLicenseFromKey rejects v1 license for wrong device', () async {
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
  });
}
