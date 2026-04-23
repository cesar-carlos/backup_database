import 'dart:io';

import 'package:backup_database/infrastructure/transfer_staging_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late Directory transferBase;
  late TransferStagingService service;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('transfer_staging_test_');
    transferBase = Directory(p.join(tempRoot.path, 'transfer'))..createSync();
    service = TransferStagingService(transferBasePath: transferBase.path);
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('copyToStaging copies file and returns posix relative path', () async {
    final sourceFile = File(p.join(tempRoot.path, 'backup.bak'))
      ..writeAsStringSync('data');

    final relative = await service.copyToStaging(sourceFile.path, 'sched-a');

    expect(relative, isNotNull);
    expect(relative, 'remote/sched-a/backup.bak');
    final staged = File(
      p.join(transferBase.path, 'remote', 'sched-a', 'backup.bak'),
    );
    expect(await staged.exists(), isTrue);
    expect(await staged.readAsString(), 'data');
  });

  test('copyToStaging copies directory tree recursively', () async {
    final sourceDir = Directory(p.join(tempRoot.path, 'my_backup'))
      ..createSync();
    File(p.join(sourceDir.path, 'a.txt')).writeAsStringSync('a');
    final sub = Directory(p.join(sourceDir.path, 'sub'))..createSync();
    File(p.join(sub.path, 'b.txt')).writeAsStringSync('b');

    final relative = await service.copyToStaging(sourceDir.path, 'sched-b');

    expect(relative, isNotNull);
    expect(relative, 'remote/sched-b/my_backup');
    final root = Directory(
      p.join(transferBase.path, 'remote', 'sched-b', 'my_backup'),
    );
    expect(await root.exists(), isTrue);
    expect(
      await File(p.join(root.path, 'a.txt')).readAsString(),
      'a',
    );
    expect(
      await File(p.join(root.path, 'sub', 'b.txt')).readAsString(),
      'b',
    );
  });

  test('copyToStaging uses remoteFolderKey when set (staging por runId)', () async {
    final sourceFile = File(p.join(tempRoot.path, 'x.bak'))..writeAsStringSync('z');
    const runKey = 'sched-1_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

    final relative = await service.copyToStaging(
      sourceFile.path,
      'sched-1',
      remoteFolderKey: runKey,
    );

    expect(relative, 'remote/$runKey/x.bak');
    final staged = File(p.join(transferBase.path, 'remote', runKey, 'x.bak'));
    expect(await staged.exists(), isTrue);
    expect(await staged.readAsString(), 'z');
  });

  test('cleanupStaging removes remoteFolderKey directory when set', () async {
    final f = File(p.join(transferBase.path, 'remote', 'k99', 'f.txt'));
    f.createSync(recursive: true);
    f.writeAsStringSync('x');

    await service.cleanupStaging('ignored', remoteFolderKey: 'k99');

    expect(
      Directory(p.join(transferBase.path, 'remote', 'k99')).existsSync(),
      isFalse,
    );
  });

  test('cleanupOldBackups remove pasta remota expirada (inteira)', () async {
    final now = DateTime.utc(2026, 6, 15, 12);
    final svc = TransferStagingService(
      transferBasePath: transferBase.path,
      clock: () => now,
    );
    final oldFile = File(p.join(transferBase.path, 'remote', 'run-a', 'x.bak'));
    oldFile.createSync(recursive: true);
    oldFile.writeAsStringSync('x');
    oldFile.setLastModifiedSync(now.subtract(const Duration(hours: 25)));

    await svc.cleanupOldBackups();

    expect(
      Directory(p.join(transferBase.path, 'remote', 'run-a')).existsSync(),
      isFalse,
    );
  });

  test('cleanupOldBackups mantem pasta dentro do TTL', () async {
    final now = DateTime.utc(2026, 6, 15, 12);
    final svc = TransferStagingService(
      transferBasePath: transferBase.path,
      clock: () => now,
    );
    final f = File(p.join(transferBase.path, 'remote', 'run-b', 'x.bak'));
    f.createSync(recursive: true);
    f.writeAsStringSync('x');
    f.setLastModifiedSync(now.subtract(const Duration(hours: 1)));

    await svc.cleanupOldBackups();

    expect(f.existsSync(), isTrue);
  });
}
