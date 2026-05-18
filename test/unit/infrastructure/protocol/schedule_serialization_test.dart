import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/protocol/schedule_serialization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('schedule_serialization', () {
    test('roundtrip preserves DatabaseType.firebird wire name', () {
      final original = Schedule(
        name: 'fb-remote',
        databaseConfigId: 'cfg-fb-1',
        databaseType: DatabaseType.firebird,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const <String>['dest-1'],
        backupFolder: r'C:\Temp\BackupDatabase',
        backupType: BackupType.fullSingle,
      );

      final map = scheduleToMap(original);
      expect(map['databaseType'], 'firebird');

      final restored = scheduleFromMap(map);
      expect(restored.databaseType, DatabaseType.firebird);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.databaseConfigId, original.databaseConfigId);
      expect(restored.backupType, original.backupType);
    });

    test('roundtrip preserves firebirdNbackupPhysicalLevel when set', () {
      final original = Schedule(
        name: 'fb-nb',
        databaseConfigId: 'cfg-fb-1',
        databaseType: DatabaseType.firebird,
        scheduleType: 'daily',
        scheduleConfig: '{}',
        destinationIds: const <String>['dest-1'],
        backupFolder: r'C:\Temp\BackupDatabase',
        backupType: BackupType.differential,
        firebirdNbackupPhysicalLevel: 3,
      );

      final map = scheduleToMap(original);
      expect(map['firebirdNbackupPhysicalLevel'], 3);

      final restored = scheduleFromMap(map);
      expect(restored.firebirdNbackupPhysicalLevel, 3);
    });
  });
}
