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
}
