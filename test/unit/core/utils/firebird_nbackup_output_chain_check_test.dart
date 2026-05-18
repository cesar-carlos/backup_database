import 'dart:io';

import 'package:backup_database/core/utils/firebird_nbackup_output_chain_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'firebird_nbackup_chain_check_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('returns null when nbackupLevel is zero', () async {
    final r = await missingFirebirdNbackupChainPattern(
      outputDirectory: tempDir.path,
      databaseStem: 'app',
      nbackupLevel: 0,
    );
    expect(r, isNull);
  });

  test('reports missing folder when outputDirectory does not exist', () async {
    final path = p.join(tempDir.path, 'nope');
    final r = await missingFirebirdNbackupChainPattern(
      outputDirectory: path,
      databaseStem: 'app',
      nbackupLevel: 1,
    );
    expect(r, isNotNull);
    expect(r, contains('pasta'));
  });

  test('level 1 requires only full nbk prefix', () async {
    final empty = await missingFirebirdNbackupChainPattern(
      outputDirectory: tempDir.path,
      databaseStem: 'app',
      nbackupLevel: 1,
    );
    expect(empty, '"app_full_*.nbk"');

    await File(p.join(tempDir.path, 'app_full_x.nbk')).writeAsString('x');
    final ok = await missingFirebirdNbackupChainPattern(
      outputDirectory: tempDir.path,
      databaseStem: 'app',
      nbackupLevel: 1,
    );
    expect(ok, isNull);
  });

  test('level 2 requires full and B1 nbk prefixes', () async {
    await File(p.join(tempDir.path, 'app_full_x.nbk')).writeAsString('x');
    final missingB1 = await missingFirebirdNbackupChainPattern(
      outputDirectory: tempDir.path,
      databaseStem: 'app',
      nbackupLevel: 2,
    );
    expect(missingB1, '"app_nbackup_B1_*.nbk"');

    await File(p.join(tempDir.path, 'app_nbackup_B1_y.nbk')).writeAsString('y');
    final ok = await missingFirebirdNbackupChainPattern(
      outputDirectory: tempDir.path,
      databaseStem: 'app',
      nbackupLevel: 2,
    );
    expect(ok, isNull);
  });

  test('matches .nbk case-insensitively', () async {
    await File(p.join(tempDir.path, 'app_full_x.NBK')).writeAsString('x');
    final r = await missingFirebirdNbackupChainPattern(
      outputDirectory: tempDir.path,
      databaseStem: 'app',
      nbackupLevel: 1,
    );
    expect(r, isNull);
  });

  test('ignores subdirectories and non-files', () async {
    await Directory(p.join(tempDir.path, 'app_full_fake')).create();
    final r = await missingFirebirdNbackupChainPattern(
      outputDirectory: tempDir.path,
      databaseStem: 'app',
      nbackupLevel: 1,
    );
    expect(r, '"app_full_*.nbk"');
  });
}
