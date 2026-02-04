import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() {
    database = AppDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  group('Database migration v14', () {
    test('fresh database has schema version 14', () async {
      final result = await database.customSelect('PRAGMA user_version').get();
      expect(result, isNotEmpty);
      final version =
          result.first.data['user_version'] as int? ??
          result.first.data.values.first as int;
      expect(version, 14);
    });

    test('v14 tables exist in fresh database', () async {
      const v14Tables = [
        'server_credentials_table',
        'connection_logs_table',
        'server_connections_table',
        'file_transfers_table',
      ];

      for (final tableName in v14Tables) {
        final rows = await database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
              variables: [Variable.withString(tableName)],
            )
            .get();
        expect(rows, isNotEmpty, reason: 'Table $tableName should exist');
      }
    });

    test('server_credentials_table is writable and readable', () async {
      final dao = database.serverCredentialDao;
      final credential = ServerCredentialsTableCompanion.insert(
        id: 'test-id',
        serverId: 'server-1',
        passwordHash: 'hash',
        name: 'Test',
        isActive: const Value(true),
        createdAt: DateTime.now(),
      );
      await dao.insertCredential(credential);
      final all = await dao.getAll();
      expect(all.length, 1);
      expect(all.first.serverId, 'server-1');
    });
  });
}
