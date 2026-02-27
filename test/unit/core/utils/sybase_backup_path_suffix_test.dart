import 'package:backup_database/core/utils/sybase_backup_path_suffix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SybaseBackupPathSuffix', () {
    test('buildDestinationName adds suffix for file with extension', () {
      final result = SybaseBackupPathSuffix.buildDestinationName(
        'mydb_full_2025-02-27.zip',
        '550e8400-e29b-41d4-a716-446655440000',
      );
      expect(result, 'mydb_full_2025-02-27_b550e8400.zip');
    });

    test('buildDestinationName adds suffix for folder name', () {
      final result = SybaseBackupPathSuffix.buildDestinationName(
        'mydb',
        '550e8400-e29b-41d4-a716-446655440000',
      );
      expect(result, 'mydb_b550e8400');
    });

    test('buildDestinationName returns baseName when backupId too short', () {
      final result = SybaseBackupPathSuffix.buildDestinationName(
        'mydb.zip',
        'short',
      );
      expect(result, 'mydb.zip');
    });

    test('extractShortIdFromPath extracts from path', () {
      const path = r'D:\Backups\2025-02-27\mydb_b550e8400\database.db';
      expect(SybaseBackupPathSuffix.extractShortIdFromPath(path), '550e8400');
    });

    test('extractShortIdFromPath returns null when no suffix', () {
      expect(
        SybaseBackupPathSuffix.extractShortIdFromPath(r'D:\Backups\mydb\file.db'),
        isNull,
      );
    });

    test('isPathProtected returns true when short id in protected set', () {
      const path = r'D:\Backups\mydb_b550e8400\file.db';
      expect(
        SybaseBackupPathSuffix.isPathProtected(path, {'550e8400'}),
        isTrue,
      );
    });

    test('isPathProtected returns false when short id not in set', () {
      const path = r'D:\Backups\mydb_b550e8400\file.db';
      expect(
        SybaseBackupPathSuffix.isPathProtected(path, {'12345678'}),
        isFalse,
      );
    });

    test('toShortIds converts full UUIDs to 8-char prefixes', () {
      const full = {
        '550e8400-e29b-41d4-a716-446655440000',
        'a1b2c3d4-e29b-41d4-a716-446655440000',
      };
      expect(
        SybaseBackupPathSuffix.toShortIds(full),
        {'550e8400', 'a1b2c3d4'},
      );
    });
  });
}
