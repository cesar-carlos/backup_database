import 'package:backup_database/application/services/license_decoder.dart';
import 'package:backup_database/application/services/license_generation_service.dart';
import 'package:backup_database/core/constants/license_constants.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_test/flutter_test.dart';

/// Testes específicos para rotação de chave Ed25519 — o decoder aceita
/// múltiplas public keys indexadas por `keyId`. Veja
/// `architectural_patterns.mdc §10` e `docs/adr/016-...` para a
/// motivação.
void main() {
  group('LicenseDecoder.publicKeysByKeyId — multi-key verification', () {
    late ed.KeyPair keyPairA;
    late ed.KeyPair keyPairB;

    setUp(() {
      keyPairA = ed.generateKey();
      keyPairB = ed.generateKey();
    });

    test('aceita licenças assinadas com qualquer keyId conhecido', () async {
      final decoder = LicenseDecoder(
        publicKeysByKeyId: {
          'ed25519-1': keyPairA.publicKey.bytes,
          'ed25519-2': keyPairB.publicKey.bytes,
        },
      );

      final genA = LicenseGenerationService(
        privateKeyBytes: keyPairA.privateKey.bytes,
        licenseDecoder: decoder,
        // Explicito mesmo coincidindo com o default — deixa óbvio que
        // este gen está pareado com a chave A (`ed25519-1`).
        // ignore: avoid_redundant_argument_values
        activeKeyId: 'ed25519-1',
      );
      final genB = LicenseGenerationService(
        privateKeyBytes: keyPairB.privateKey.bytes,
        licenseDecoder: decoder,
        activeKeyId: 'ed25519-2',
      );

      final licA = await genA.generateLicenseKey(
        deviceKey: 'device-multi',
        allowedFeatures: const ['feat'],
      );
      final licB = await genB.generateLicenseKey(
        deviceKey: 'device-multi',
        allowedFeatures: const ['feat'],
      );

      final decA = await decoder.decode(licA.getOrNull()!);
      final decB = await decoder.decode(licB.getOrNull()!);

      expect(decA.isSuccess(), isTrue);
      expect(decB.isSuccess(), isTrue);
      expect(decA.getOrNull()!['keyId'], 'ed25519-1');
      expect(decB.getOrNull()!['keyId'], 'ed25519-2');
    });

    test(
      'rejeita licença assinada com chave que NÃO está no decoder '
      '(ataque: keyId inventado)',
      () async {
        // Decoder só conhece chave A. Atacante gera com chave B e
        // marca como `ed25519-2`. Deve ser rejeitada.
        final decoder = LicenseDecoder(
          publicKeysByKeyId: {
            'ed25519-1': keyPairA.publicKey.bytes,
          },
        );

        final hostileGen = LicenseGenerationService(
          privateKeyBytes: keyPairB.privateKey.bytes,
          licenseDecoder: decoder, // decoder não importa pro gen.
          activeKeyId: 'ed25519-2', // não está no decoder
        );

        final lic = await hostileGen.generateLicenseKey(
          deviceKey: 'device-attacker',
          allowedFeatures: const ['admin', 'remote_control'],
        );

        final dec = await decoder.decode(lic.getOrNull()!);
        expect(dec.isError(), isTrue);
        expect(
          dec.exceptionOrNull()!.toString(),
          contains('keyId desconhecido'),
        );
      },
    );

    test(
      'rejeita licença assinada com keyId conhecido MAS chave errada '
      '(ataque: forjar assinatura com keyId falso)',
      () async {
        // Decoder mapeia ed25519-1 -> chave A. Atacante assina com
        // chave B mas marca o payload como `ed25519-1`. Verifier vai
        // tentar com chave A → falha de assinatura.
        final decoder = LicenseDecoder(
          publicKeysByKeyId: {
            'ed25519-1': keyPairA.publicKey.bytes,
          },
        );

        final hostileGen = LicenseGenerationService(
          privateKeyBytes: keyPairB.privateKey.bytes,
          licenseDecoder: decoder,
          // Explícito por clareza: o atacante usa o keyId que o cliente
          // reconhece, mas assina com chave errada.
          // ignore: avoid_redundant_argument_values
          activeKeyId: 'ed25519-1',
        );

        final lic = await hostileGen.generateLicenseKey(
          deviceKey: 'device-attacker',
          allowedFeatures: const ['admin'],
        );

        final dec = await decoder.decode(lic.getOrNull()!);
        expect(dec.isError(), isTrue);
        expect(
          dec.exceptionOrNull()!.toString(),
          contains('Assinatura'),
        );
      },
    );

    test('acceptedKeyIds expõe todas as chaves registradas', () {
      final decoder = LicenseDecoder(
        publicKeysByKeyId: {
          'ed25519-1': keyPairA.publicKey.bytes,
          'ed25519-2': keyPairB.publicKey.bytes,
        },
      );
      expect(
        decoder.acceptedKeyIds.toSet(),
        equals({'ed25519-1', 'ed25519-2'}),
      );
    });

    test('rejeita construção com mapa vazio', () {
      expect(
        () => LicenseDecoder(publicKeysByKeyId: const {}),
        throwsArgumentError,
      );
    });

    test('rejeita construção com chave de tamanho inválido', () {
      expect(
        () => LicenseDecoder(
          publicKeysByKeyId: {
            'bad': [1, 2, 3],
          },
        ),
        throwsArgumentError,
      );
    });
  });

  group('LicenseGenerationService.activeKeyId', () {
    test('default é LicenseConstants.keyIdDefault', () {
      final keyPair = ed.generateKey();
      final decoder = LicenseDecoder(
        publicKeysByKeyId: {
          LicenseConstants.keyIdDefault: keyPair.publicKey.bytes,
        },
      );
      final gen = LicenseGenerationService(
        privateKeyBytes: keyPair.privateKey.bytes,
        licenseDecoder: decoder,
      );
      expect(gen.activeKeyId, LicenseConstants.keyIdDefault);
    });

    test('override é refletido no payload das licenças geradas', () async {
      final keyPair = ed.generateKey();
      final decoder = LicenseDecoder(
        publicKeysByKeyId: {
          'meu-key-id-customizado': keyPair.publicKey.bytes,
        },
      );
      final gen = LicenseGenerationService(
        privateKeyBytes: keyPair.privateKey.bytes,
        licenseDecoder: decoder,
        activeKeyId: 'meu-key-id-customizado',
      );

      final lic = await gen.generateLicenseKey(
        deviceKey: 'device-custom',
        allowedFeatures: const ['feat'],
      );
      final dec = await decoder.decode(lic.getOrNull()!);

      expect(dec.isSuccess(), isTrue);
      expect(dec.getOrNull()!['keyId'], 'meu-key-id-customizado');
      expect(gen.activeKeyId, 'meu-key-id-customizado');
    });
  });
}
