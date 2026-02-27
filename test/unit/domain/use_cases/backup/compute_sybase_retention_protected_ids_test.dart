import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/use_cases/backup/compute_sybase_retention_protected_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ComputeSybaseRetentionProtectedIds useCase;

  setUp(() {
    useCase = const ComputeSybaseRetentionProtectedIds();
  });

  BackupHistory full({
    required String id,
    required DateTime startedAt,
    DateTime? finishedAt,
    Map<String, dynamic>? sybaseOptions,
  }) {
    return BackupHistory(
      id: id,
      scheduleId: 's1',
      databaseName: 'db',
      databaseType: 'sybase',
      backupPath: '/path/$id.db',
      fileSize: 1000,
      status: BackupStatus.success,
      startedAt: startedAt,
      finishedAt: finishedAt ?? startedAt.add(const Duration(minutes: 5)),
      metrics: sybaseOptions != null
          ? BackupMetrics(
              totalDuration: Duration.zero,
              backupDuration: Duration.zero,
              verifyDuration: Duration.zero,
              backupSizeBytes: 1000,
              backupSpeedMbPerSec: 0,
              backupType: 'full',
              flags: const BackupFlags(
                compression: false,
                verifyPolicy: 'none',
                stripingCount: 1,
                withChecksum: false,
                stopOnError: true,
              ),
              sybaseOptions: sybaseOptions,
            )
          : null,
    );
  }

  BackupHistory log({
    required String id,
    required String baseFullId,
    required DateTime startedAt,
    int logSequence = 1,
  }) {
    return BackupHistory(
      id: id,
      scheduleId: 's1',
      databaseName: 'db',
      databaseType: 'sybase',
      backupPath: '/path/$id.trn',
      fileSize: 100,
      backupType: 'log',
      status: BackupStatus.success,
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(minutes: 1)),
      metrics: BackupMetrics(
        totalDuration: Duration.zero,
        backupDuration: Duration.zero,
        verifyDuration: Duration.zero,
        backupSizeBytes: 100,
        backupSpeedMbPerSec: 0,
        backupType: 'log',
        flags: const BackupFlags(
          compression: false,
          verifyPolicy: 'none',
          stripingCount: 1,
          withChecksum: false,
          stopOnError: true,
        ),
        sybaseOptions: {
          'baseFullId': baseFullId,
          'logSequence': logSequence,
        },
      ),
    );
  }

  group('ComputeSybaseRetentionProtectedIds', () {
    test('returns empty when no histories', () {
      final result = useCase(histories: [], retentionDays: 30);
      expect(result, isEmpty);
    });

    test('protects single full within retention', () {
      final now = DateTime.now();
      final full1 = full(
        id: 'f1',
        startedAt: now.subtract(const Duration(days: 5)),
        sybaseOptions: {'baseFullId': 'f1', 'chainStartAt': now.toIso8601String()},
      );
      final result = useCase(histories: [full1], retentionDays: 30);
      expect(result, contains('f1'));
    });

    test('protects full and its logs within retention', () {
      final now = DateTime.now();
      final base = now.subtract(const Duration(days: 5));
      final full1 = full(
        id: 'f1',
        startedAt: base,
        sybaseOptions: {'baseFullId': 'f1'},
      );
      final log1 = log(id: 'l1', baseFullId: 'f1', startedAt: base.add(const Duration(hours: 1)));
      final log2 = log(id: 'l2', baseFullId: 'f1', startedAt: base.add(const Duration(hours: 2)), logSequence: 2);
      final result = useCase(
        histories: [full1, log1, log2],
        retentionDays: 30,
      );
      expect(result, containsAll(['f1', 'l1', 'l2']));
    });

    test('protects last full chain even when expired', () {
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 60));
      final full1 = full(id: 'f1', startedAt: old);
      final log1 = log(id: 'l1', baseFullId: 'f1', startedAt: old.add(const Duration(hours: 1)));
      final result = useCase(
        histories: [full1, log1],
        retentionDays: 30,
      );
      expect(result, containsAll(['f1', 'l1']));
    });

    test('does not protect expired chain when newer full exists', () {
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 60));
      final recent = now.subtract(const Duration(days: 5));
      final full1 = full(id: 'f1', startedAt: old);
      final log1 = log(id: 'l1', baseFullId: 'f1', startedAt: old.add(const Duration(hours: 1)));
      final full2 = full(
        id: 'f2',
        startedAt: recent,
        sybaseOptions: {'baseFullId': 'f2'},
      );
      final result = useCase(
        histories: [full1, log1, full2],
        retentionDays: 30,
      );
      expect(result, containsAll(['f2']));
      expect(result, isNot(contains('f1')));
      expect(result, isNot(contains('l1')));
    });

    test('ignores failed backups', () {
      final now = DateTime.now();
      final full1 = full(id: 'f1', startedAt: now.subtract(const Duration(days: 5)));
      final failedFull = BackupHistory(
        id: 'f2',
        scheduleId: 's1',
        databaseName: 'db',
        databaseType: 'sybase',
        backupPath: '/path/f2.db',
        fileSize: 0,
        status: BackupStatus.error,
        startedAt: now.subtract(const Duration(days: 10)),
      );
      final result = useCase(
        histories: [full1, failedFull],
        retentionDays: 30,
      );
      expect(result, contains('f1'));
      expect(result, isNot(contains('f2')));
    });
  });
}
