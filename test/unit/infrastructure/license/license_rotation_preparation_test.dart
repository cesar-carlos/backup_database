import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/infrastructure/license/license_public_keys.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../scripts/generate_license_keypair.dart' as generator;

void main() {
  tearDown(dotenv.clean);

  test('CLI never writes the private key to stdout', () async {
    final parent = await Directory.systemTemp.createTemp('signing-cli-');
    addTearDown(() => parent.delete(recursive: true));
    final output = <String>[];
    await runZoned(
      () => generator.main(['cli-test', parent.path]),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => output.add(line),
      ),
    );
    final folder = await parent
        .list()
        .where((entry) => entry is Directory)
        .first;
    final signing = await File('${folder.path}/signer.env').readAsString();
    final secret = signing
        .split('\n')
        .firstWhere(
          (line) => line.startsWith('BACKUP_DATABASE_LICENSE_PRIVATE_KEY='),
        )
        .split('=')
        .skip(1)
        .join('=');
    expect(output.join('\n').contains(secret), isFalse);
    expect(output.join('\n'), contains('No installed key'));
  });

  test(
    'rejects legacy key ID and repository output before generating',
    () async {
      await expectLater(
        generator.prepareKeypair('ed25519-1', Directory.systemTemp.path),
        throwsArgumentError,
      );
      await expectLater(
        generator.prepareKeypair('new-key', Directory.current.path),
        throwsArgumentError,
      );
      await expectLater(
        generator.prepareKeypair('bad\nkey', Directory.systemTemp.path),
        throwsArgumentError,
      );
    },
  );

  test(
    'prepares matching signing key and new-only trust without printing secrets',
    () async {
      final directory = await generator.prepareKeypair(
        'rotation-test',
        Directory.systemTemp.path,
      );
      addTearDown(() => directory.delete(recursive: true));
      final signing = await File('${directory.path}/signer.env').readAsString();
      final public = await File('${directory.path}/public.env').readAsString();
      final privateLine = signing
          .split('\n')
          .firstWhere(
            (line) => line.startsWith('BACKUP_DATABASE_LICENSE_PRIVATE_KEY='),
          );
      final privateBytes = base64Decode(
        privateLine.substring(privateLine.indexOf('=') + 1),
      );
      expect(public.contains(base64Encode(privateBytes)), isFalse);
      dotenv.loadFromString(envString: public);
      final keys = LicensePublicKeys.fromEnv().getOrThrow();
      expect(keys.keys, ['rotation-test']);
      final payload = utf8.encode('rotation-regression');
      final signature = ed.sign(ed.PrivateKey(privateBytes), payload);
      expect(
        ed.verify(ed.PublicKey(keys['rotation-test']!), payload, signature),
        isTrue,
      );
      // A second preparation never overwrites the first private key.
      final other = await generator.prepareKeypair(
        'rotation-test',
        Directory.systemTemp.path,
      );
      addTearDown(() => other.delete(recursive: true));
      expect(other.path == directory.path, isFalse);
      expect(
        await File('${directory.path}/signer.env').readAsString() == signing,
        isTrue,
      );
    },
  );
}
