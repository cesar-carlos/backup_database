import 'dart:async';

import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/infrastructure/repositories/cached_backup_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart' as rd;

BackupHistory _history(
  String id, {
  BackupStatus status = BackupStatus.success,
}) {
  return BackupHistory(
    id: id,
    scheduleId: 's',
    databaseName: 'db',
    databaseType: 'sqlite',
    backupPath: '/tmp/$id.bak',
    fileSize: 100,
    status: status,
    startedAt: DateTime.now(),
  );
}

/// Repositório fake instrumentado para simular cenários de cache.
class _FakeBackupHistoryRepository implements IBackupHistoryRepository {
  final List<List<BackupHistory>> getAllResponses = [];
  int getAllCalls = 0;
  Completer<void>? blockGetAll;

  @override
  Future<rd.Result<List<BackupHistory>>> getAll({
    int? limit,
    int? offset,
  }) async {
    getAllCalls++;
    if (blockGetAll != null) await blockGetAll!.future;
    if (getAllResponses.isEmpty) return const rd.Success([]);
    return rd.Success(getAllResponses.removeAt(0));
  }

  @override
  Future<rd.Result<BackupHistory>> create(BackupHistory history) async {
    return rd.Success(history);
  }

  @override
  Future<rd.Result<BackupHistory>> update(BackupHistory history) async {
    return rd.Success(history);
  }

  @override
  Future<rd.Result<void>> delete(String id) async => const rd.Success(());

  @override
  Future<rd.Result<List<BackupHistory>>> getBySchedule(
    String scheduleId,
  ) async {
    return const rd.Success([]);
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByStatus(
    BackupStatus status,
  ) async {
    return const rd.Success([]);
  }

  @override
  Future<rd.Result<List<BackupHistory>>> getByDateRange(
    DateTime start,
    DateTime end,
  ) async => const rd.Success([]);

  @override
  Future<rd.Result<BackupHistory>> getById(String id) async {
    return rd.Success(_history(id));
  }

  @override
  Future<rd.Result<BackupHistory>> getByRunId(String runId) async {
    return rd.Success(_history(runId));
  }

  @override
  Future<rd.Result<BackupHistory>> getLastBySchedule(String scheduleId) async {
    return rd.Success(_history(scheduleId));
  }

  @override
  Future<rd.Result<int>> deleteOlderThan(DateTime date) async {
    return const rd.Success(0);
  }

  @override
  Future<rd.Result<int>> reconcileStaleRunning({
    required Duration maxAge,
  }) async => const rd.Success(0);

  @override
  Future<rd.Result<BackupHistory>> updateHistoryAndLogIfRunning({
    required BackupHistory history,
    required String logStep,
    required LogLevel logLevel,
    required String logMessage,
    String? logDetails,
  }) async => rd.Success(history);

  @override
  Future<rd.Result<BackupHistory>> updateIfRunning(
    BackupHistory history,
  ) async {
    return rd.Success(history);
  }
}

void main() {
  late _FakeBackupHistoryRepository fake;
  late CachedBackupHistoryRepository cached;

  setUp(() {
    fake = _FakeBackupHistoryRepository();
    cached = CachedBackupHistoryRepository(repository: fake);
  });

  group('CachedBackupHistoryRepository — basic caching', () {
    test('caches getAll response on second call', () async {
      fake.getAllResponses
        ..add([_history('a'), _history('b')])
        ..add([_history('a'), _history('b')]);

      final first = await cached.getAll();
      final second = await cached.getAll();

      expect(first.isSuccess(), isTrue);
      expect(second.isSuccess(), isTrue);
      expect(fake.getAllCalls, 1, reason: 'second call should hit cache');
    });

    test('write (create) invalidates cache', () async {
      fake.getAllResponses
        ..add([_history('a')])
        ..add([_history('a'), _history('b')]);

      await cached.getAll();
      await cached.create(_history('b'));
      await cached.getAll();

      expect(fake.getAllCalls, 2);
    });

    test(
      'returned list is immutable (mutation does not corrupt cache)',
      () async {
        fake.getAllResponses
          ..add([_history('a'), _history('b')])
          ..add([_history('a'), _history('b'), _history('c')]);

        final first = await cached.getAll();
        final firstList = first.getOrNull()!;
        // Tentativa de mutação deve falhar (lista cacheada é UnmodifiableListView).
        expect(() => firstList.add(_history('z')), throwsUnsupportedError);

        final second = await cached.getAll();
        expect(
          second.getOrNull()!.length,
          2,
          reason: 'cache should not have been corrupted by caller mutation',
        );
      },
    );
  });

  group(
    'CachedBackupHistoryRepository — race TOCTOU (write durante leitura)',
    () {
      test(
        'cache NÃO armazena snapshot stale quando write ocorre durante leitura',
        () async {
          // Configura: getAll retorna snapshot V1; em paralelo, um write
          // (invalidação) acontece; o cache não deve persistir V1.
          fake.getAllResponses.add([_history('v1')]);
          fake.blockGetAll = Completer<void>();

          final readingFuture = cached.getAll();
          // Enquanto o read está bloqueado, dispara write (invalida).
          await cached.create(_history('new'));
          // Libera o read.
          fake.blockGetAll!.complete();
          await readingFuture;

          // Próximo getAll deve voltar ao repo (cache não foi populado
          // porque a versão mudou durante o read).
          fake.getAllResponses.add([_history('v2'), _history('new')]);
          final second = await cached.getAll();
          expect(fake.getAllCalls, 2);
          expect(second.getOrNull()!.length, 2);
        },
      );
    },
  );
}
