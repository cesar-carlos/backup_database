import 'dart:io';

import 'package:backup_database/core/utils/sha256_verifier.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('verifyFileSha256', () {
    test('returns Failure when file does not exist', () async {
      final result = await verifyFileSha256('/nonexistent/path/file.db');

      expect(result, isA<Sha256VerificationFailure>());
      expect(
        (result as Sha256VerificationFailure).message,
        contains('não encontrado'),
      );
    });

    test('returns Failure when sidecar does not exist', () async {
      final tempDir = await Directory.systemTemp.createTemp();
      final file = File('${tempDir.path}/test.db')..writeAsStringSync('data');

      try {
        final result = await verifyFileSha256(file.path);

        expect(result, isA<Sha256VerificationFailure>());
        expect(
          (result as Sha256VerificationFailure).message,
          contains('sidecar'),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns Failure when sidecar has invalid format', () async {
      final tempDir = await Directory.systemTemp.createTemp();
      final file = File('${tempDir.path}/test.db')..writeAsStringSync('data');
      File('${tempDir.path}/test.db.sha256').writeAsStringSync('not-a-valid-hash');

      try {
        final result = await verifyFileSha256(file.path);

        expect(result, isA<Sha256VerificationFailure>());
        expect(
          (result as Sha256VerificationFailure).message,
          contains('inválido'),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns Failure when hash does not match', () async {
      final tempDir = await Directory.systemTemp.createTemp();
      final file = File('${tempDir.path}/test.db')..writeAsStringSync('data');
      File('${tempDir.path}/test.db.sha256').writeAsStringSync(
        '0' * 64 + '  test.db',
      );

      try {
        final result = await verifyFileSha256(file.path);

        expect(result, isA<Sha256VerificationFailure>());
        expect(
          (result as Sha256VerificationFailure).message,
          contains('Integridade falhou'),
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns Ok when hash matches', () async {
      final tempDir = await Directory.systemTemp.createTemp();
      final file = File('${tempDir.path}/test.db')..writeAsStringSync('data');

      final digest = sha256.convert(await file.readAsBytes());
      final expectedHash = digest.toString();
      File('${tempDir.path}/test.db.sha256')
          .writeAsStringSync('$expectedHash  test.db');

      try {
        final result = await verifyFileSha256(file.path);

        expect(result, isA<Sha256VerificationOk>());
        final ok = result as Sha256VerificationOk;
        expect(ok.hash, expectedHash);
        expect(ok.fileSize, 4);
        expect(ok.durationMs, greaterThanOrEqualTo(0));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
