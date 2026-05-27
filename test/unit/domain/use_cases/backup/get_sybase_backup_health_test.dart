import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/use_cases/backup/get_sybase_backup_health.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

void main() {
  late _MockBackupHistoryRepository repository;
  late GetSybaseBackupHealth useCase;

  setUp(() {
    repository = _MockBackupHistoryRepository();
    useCase = GetSybaseBackupHealth(repository, maxDaysForBaseFull: 7);
  });

  BackupHistory build({
    required String id,
    required BackupType type,
    required BackupStatus status,
    required DateTime startedAt,
    DateTime? finishedAt,
    String databaseType = 'sybase',
  }) {
    return BackupHistory(
      id: id,
      databaseName: 'db',
      databaseType: databaseType,
      backupPath: '/p/$id',
      fileSize: 1,
      status: status,
      startedAt: startedAt,
      finishedAt: finishedAt ?? startedAt,
      backupType: type.name,
    );
  }

  group('GetSybaseBackupHealth', () {
    test('retorna ok quando full recente e sem erros', () async {
      final now = DateTime.now();
      when(() => repository.getAll(limit: any(named: 'limit'))).thenAnswer(
        (_) async => rd.Success([
          build(
            id: 'f1',
            type: BackupType.full,
            status: BackupStatus.success,
            startedAt: now.subtract(const Duration(days: 1)),
          ),
          build(
            id: 'l1',
            type: BackupType.log,
            status: BackupStatus.success,
            startedAt: now.subtract(const Duration(hours: 2)),
          ),
        ]),
      );

      final result = await useCase();
      expect(result.isSuccess(), isTrue);

      final health = result.getOrNull()!;
      expect(health.chainStatus, SybaseChainStatus.ok);
      expect(health.lastFull?.id, 'f1');
      expect(health.lastLog?.id, 'l1');
    });

    test('retorna broken quando há logs mas nenhum full', () async {
      final now = DateTime.now();
      when(() => repository.getAll(limit: any(named: 'limit'))).thenAnswer(
        (_) async => rd.Success([
          build(
            id: 'l1',
            type: BackupType.log,
            status: BackupStatus.success,
            startedAt: now,
          ),
        ]),
      );

      final result = await useCase();
      final health = result.getOrNull()!;
      expect(health.chainStatus, SybaseChainStatus.broken);
      expect(health.lastFull, isNull);
      expect(health.lastLog?.id, 'l1');
    });

    test('retorna warning quando full está expirado', () async {
      final now = DateTime.now();
      when(() => repository.getAll(limit: any(named: 'limit'))).thenAnswer(
        (_) async => rd.Success([
          build(
            id: 'old-full',
            type: BackupType.full,
            status: BackupStatus.success,
            startedAt: now.subtract(const Duration(days: 30)),
          ),
        ]),
      );

      final result = await useCase();
      final health = result.getOrNull()!;
      expect(health.chainStatus, SybaseChainStatus.warning);
    });

    test('retorna warning quando último backup foi error', () async {
      final now = DateTime.now();
      when(() => repository.getAll(limit: any(named: 'limit'))).thenAnswer(
        (_) async => rd.Success([
          build(
            id: 'f1',
            type: BackupType.full,
            status: BackupStatus.success,
            startedAt: now.subtract(const Duration(days: 1)),
          ),
          build(
            id: 'failed-log',
            type: BackupType.log,
            status: BackupStatus.error,
            startedAt: now.subtract(const Duration(minutes: 30)),
          ),
        ]),
      );

      final result = await useCase();
      final health = result.getOrNull()!;
      expect(health.chainStatus, SybaseChainStatus.warning);
    });

    test('ignora backups de outros databaseTypes', () async {
      final now = DateTime.now();
      when(() => repository.getAll(limit: any(named: 'limit'))).thenAnswer(
        (_) async => rd.Success([
          build(
            id: 'sql-full',
            type: BackupType.full,
            status: BackupStatus.success,
            startedAt: now,
            databaseType: 'sqlServer',
          ),
        ]),
      );

      final result = await useCase();
      final health = result.getOrNull()!;
      // Sem nenhum backup Sybase, nem full nem log → cadeia OK (nada
      // a verificar) e lastFull/lastLog null.
      expect(health.chainStatus, SybaseChainStatus.ok);
      expect(health.lastFull, isNull);
      expect(health.lastLog, isNull);
    });

    test('aceita fullSingle como full bem-sucedido (compat legado)', () async {
      final now = DateTime.now();
      when(() => repository.getAll(limit: any(named: 'limit'))).thenAnswer(
        (_) async => rd.Success([
          build(
            id: 'fs',
            type: BackupType.fullSingle,
            status: BackupStatus.success,
            startedAt: now.subtract(const Duration(days: 1)),
          ),
        ]),
      );

      final result = await useCase();
      final health = result.getOrNull()!;
      expect(health.chainStatus, SybaseChainStatus.ok);
      expect(health.lastFull?.id, 'fs');
    });

    test('propaga falha do repositório como Failure', () async {
      when(() => repository.getAll(limit: any(named: 'limit'))).thenAnswer(
        (_) async => rd.Failure(Exception('db down')),
      );

      final result = await useCase();
      expect(result.isError(), isTrue);
    });
  });
}
