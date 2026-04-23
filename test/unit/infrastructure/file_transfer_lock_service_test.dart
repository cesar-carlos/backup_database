import 'dart:convert';
import 'dart:io';

import 'package:backup_database/infrastructure/file_transfer_lease.dart';
import 'package:backup_database/infrastructure/file_transfer_lock_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _lockFileNameForPath(String filePath) {
  final key = p.normalize(p.absolute(filePath));
  return '${key.hashCode.toUnsigned(16).toRadixString(16).padLeft(8, '0')}.lock';
}

void main() {
  group('FileTransferLockService', () {
    late Directory tempDir;
    const fp = r'C:\data\remote\k\file.zip';
    var now = DateTime.utc(2026, 4, 23, 12);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ft_lease_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    FileTransferLockService svc() => FileTransferLockService(
      lockBasePath: tempDir.path,
      clock: () => now,
    );

    test('v1: nega outro owner com runId distinto', () async {
      final s = svc();
      expect(await s.tryAcquireLock(fp, owner: 'a', runId: 'r1'), isTrue);
      expect(await s.tryAcquireLock(fp, owner: 'b', runId: 'r2'), isFalse);
    });

    test('v1: mesmo runId permite re-adquire de outro owner (re-sincronizacao)', () async {
      final s = svc();
      expect(await s.tryAcquireLock(fp, owner: 'a', runId: 'r1'), isTrue);
      expect(await s.tryAcquireLock(fp, owner: 'b', runId: 'r1'), isTrue);
    });

    test('mesmo owner re-adquire (refresh)', () async {
      final s = svc();
      expect(await s.tryAcquireLock(fp, owner: 'a', runId: 'r1'), isTrue);
      now = now.add(const Duration(minutes: 5));
      expect(await s.tryAcquireLock(fp, owner: 'a', runId: 'r1'), isTrue);
    });

    test('apos expiracao, outro adquire', () async {
      final s = svc();
      expect(await s.tryAcquireLock(fp, owner: 'a', leaseTtl: const Duration(minutes: 2)), isTrue);
      now = now.add(const Duration(minutes: 3));
      expect(await s.tryAcquireLock(fp, owner: 'b'), isTrue);
    });

    test('lock legado (so ISO) bloqueia ate expirar', () async {
      final s = svc();
      final lockFile = File(p.join(tempDir.path, _lockFileNameForPath(fp)));
      await lockFile.writeAsString(DateTime.utc(2026, 4, 23, 12).toIso8601String());
      now = DateTime.utc(2026, 4, 23, 12, 15);
      expect(
        await s.tryAcquireLock(fp, owner: 'a'),
        isFalse,
      );
    });

    test('isLocked falso quando v1 expirou (arquivo ainda no disco)', () async {
      final s = svc();
      expect(await s.tryAcquireLock(fp, owner: 'a', leaseTtl: const Duration(minutes: 1)), isTrue);
      expect(await s.isLocked(fp), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(await s.isLocked(fp), isFalse);
    });

    test('releaseLock remove o arquivo', () async {
      final s = svc();
      await s.tryAcquireLock(fp, owner: 'a');
      await s.releaseLock(fp);
      expect(await s.isLocked(fp), isFalse);
    });

    test('cleanupExpiredLocks remove v1 expirado', () async {
      final s = svc();
      final f = File(p.join(tempDir.path, _lockFileNameForPath(fp)));
      final lease = FileTransferLeaseV1(
        filePath: fp,
        owner: 'x',
        acquiredAt: now,
        expiresAt: now.add(const Duration(minutes: 1)),
      );
      await f.writeAsString(jsonEncode(lease.toJson()));
      now = now.add(const Duration(hours: 1));
      await s.cleanupExpiredLocks();
      expect(await f.exists(), isFalse);
    });

    test('fileTransferSameLeaseHolder', () {
      final l = FileTransferLeaseV1(
        filePath: 'p',
        owner: 'a',
        acquiredAt: now,
        expiresAt: now,
        runId: 'r',
      );
      expect(
        fileTransferSameLeaseHolder(
          existing: l,
          owner: 'a',
          runId: 'x',
        ),
        isTrue,
      );
      expect(
        fileTransferSameLeaseHolder(
          existing: l,
          owner: 'b',
          runId: 'r',
        ),
        isTrue,
      );
      expect(
        fileTransferSameLeaseHolder(
          existing: l,
          owner: 'b',
          runId: 'x',
        ),
        isFalse,
      );
    });
  });
}
