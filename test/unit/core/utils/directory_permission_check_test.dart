import 'dart:io';

import 'package:backup_database/core/utils/directory_permission_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'directory_permission_check_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DirectoryPermissionCheck.hasWritePermission', () {
    test(
      'returns true for a writable directory',
      () async {
        final ok = await DirectoryPermissionCheck.hasWritePermission(tempDir);
        expect(ok, isTrue);
      },
    );

    test(
      'returns false for a non-existent directory',
      () async {
        final ghost = Directory(p.join(tempDir.path, 'does-not-exist'));
        final ok = await DirectoryPermissionCheck.hasWritePermission(ghost);
        expect(
          ok,
          isFalse,
          reason: 'writeAsString in a non-existent dir should fail',
        );
      },
    );

    test(
      'cleans up the probe file after a successful check',
      () async {
        await DirectoryPermissionCheck.hasWritePermission(tempDir);

        // O probe file deve ter sido removido — não deve haver
        // arquivos `.backup_permission_test_*` deixados pra trás.
        final leftovers = tempDir
            .listSync()
            .whereType<File>()
            .where((f) => p.basename(f.path).startsWith('.backup_permission_test_'))
            .toList();
        expect(
          leftovers,
          isEmpty,
          reason: 'probe file must be cleaned up after the check',
        );
      },
    );

    test(
      'multiple parallel checks do not collide (timestamp differentiation)',
      () async {
        // Todos os checks devem suceder sem corromper-se mutuamente.
        // A diferenciação por `millisecondsSinceEpoch` é o que evita
        // colisão; chamadas síncronas suficientemente rápidas poderiam
        // bater no mesmo timestamp, mas mesmo assim cada operação é
        // sequencial dentro do isolate (Dart single-threaded).
        final results = await Future.wait([
          DirectoryPermissionCheck.hasWritePermission(tempDir),
          DirectoryPermissionCheck.hasWritePermission(tempDir),
          DirectoryPermissionCheck.hasWritePermission(tempDir),
        ]);

        expect(results, everyElement(isTrue));
      },
    );

    test('does not throw on any internal error (defensive)', () async {
      // Mesmo se a probe falhar por motivo inesperado, o método deve
      // retornar `false` em vez de propagar a exception. Esse contrato
      // é importante para callers que usam o boolean para decidir
      // mensagem de erro ao usuário.
      final ghost = Directory(p.join(tempDir.path, 'does-not-exist'));
      await expectLater(
        DirectoryPermissionCheck.hasWritePermission(ghost),
        completes,
      );
    });
  });

  group('DirectoryPermissionCheck.hasWritePermissionForPath', () {
    test('delegates to hasWritePermission with Directory(path)', () async {
      final ok = await DirectoryPermissionCheck.hasWritePermissionForPath(
        tempDir.path,
      );
      expect(ok, isTrue);
    });

    test('returns false for non-existent path', () async {
      final ghostPath = p.join(tempDir.path, 'does-not-exist');
      final ok = await DirectoryPermissionCheck.hasWritePermissionForPath(
        ghostPath,
      );
      expect(ok, isFalse);
    });
  });
}
