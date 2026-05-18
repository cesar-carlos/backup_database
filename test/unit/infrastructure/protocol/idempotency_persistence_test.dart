import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_policy.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_store.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdempotencyRegistry persistence', () {
    late AppDatabase database;
    late IdempotencyRegistry registry;

    setUp(() {
      database = AppDatabase.inMemory();
      registry = IdempotencyRegistry(
        ttl: IdempotencyPolicy.defaultTtl,
        store: DriftIdempotencyStore(database.idempotencyDao),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('should return cached response after registry restart simulation',
        () async {
      var calls = 0;
      final response = createStartBackupResponse(
        requestId: 1,
        runId: 'run-1',
        state: ExecutionState.running,
        scheduleId: 'sch-1',
        serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
      );

      await registry.runIdempotent<Message>(
        key: 'key-a',
        compute: () async {
          calls++;
          return response;
        },
      );

      final registryAfterRestart = IdempotencyRegistry(
        ttl: IdempotencyPolicy.defaultTtl,
        store: DriftIdempotencyStore(database.idempotencyDao),
      );

      final cached = await registryAfterRestart.runIdempotent<Message>(
        key: 'key-a',
        compute: () async {
          calls++;
          return createStartBackupResponse(
            requestId: 2,
            runId: 'run-2',
            state: ExecutionState.running,
            scheduleId: 'sch-2',
            serverTimeUtc: DateTime.utc(2026, 4, 19, 12),
          );
        },
      );

      expect(calls, 1);
      expect(cached.header.type, MessageType.startBackupResponse);
      expect(cached.payload['runId'], 'run-1');
    });
  });
}
