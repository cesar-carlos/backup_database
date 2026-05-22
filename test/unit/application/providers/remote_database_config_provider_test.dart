import 'dart:io';

import 'package:backup_database/application/providers/remote_database_config_provider.dart';
import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../helpers/fake_remote_database_config_connection_manager.dart';

void main() {
  setUpAll(() {
    if (!di.getIt.isRegistered<SocketLoggerService>()) {
      di.getIt.registerSingleton<SocketLoggerService>(
        SocketLoggerService(logsDirectory: Directory.systemTemp.path),
      );
    }
  });

  late FakeRemoteDatabaseConfigConnectionManager connectionManager;
  late RemoteDatabaseConfigProvider provider;

  setUp(() {
    connectionManager = FakeRemoteDatabaseConfigConnectionManager();
    provider = RemoteDatabaseConfigProvider(connectionManager);
  });

  group('RemoteDatabaseConfigProvider.loadConfigs', () {
    test(
      'should merge lists from all types except firebird when unsupported',
      () async {
        connectionManager.listResultsByType = {
          RemoteDatabaseType.sqlServer: rd.Success(
            DatabaseConfigListResult(
              databaseType: RemoteDatabaseType.sqlServer,
              configs: const [
                {'id': 'sql-1', 'name': 'Prod SQL'},
              ],
              serverTimeUtc: DateTime.utc(2026),
            ),
          ),
          RemoteDatabaseType.sybase: rd.Success(
            DatabaseConfigListResult(
              databaseType: RemoteDatabaseType.sybase,
              configs: const [
                {'id': 'syb-1', 'name': 'ERP'},
              ],
              serverTimeUtc: DateTime.utc(2026),
            ),
          ),
          RemoteDatabaseType.postgres: rd.Success(
            DatabaseConfigListResult(
              databaseType: RemoteDatabaseType.postgres,
              configs: const <Map<String, dynamic>>[],
              serverTimeUtc: DateTime.utc(2026),
            ),
          ),
          RemoteDatabaseType.firebird: rd.Success(
            DatabaseConfigListResult(
              databaseType: RemoteDatabaseType.firebird,
              configs: const [
                {'id': 'fb-1', 'name': 'Should not load'},
              ],
              serverTimeUtc: DateTime.utc(2026),
            ),
          ),
        };

        await provider.loadConfigs();

        expect(provider.entries.length, 2);
        expect(
          provider.entries.map((e) => e.id).toList(),
          containsAll(<String>['sql-1', 'syb-1']),
        );
        expect(connectionManager.listRemoteDatabaseConfigsCallCount, 3);
      },
    );
  });

  group('RemoteDatabaseConfigProvider.testConnection', () {
    test('should return server error message when probe fails', () async {
      const entry = RemoteDatabaseConfigEntry(
        id: 'sql-1',
        name: 'Prod',
        databaseType: RemoteDatabaseType.sqlServer,
      );
      connectionManager.testConnectionResult = rd.Success(
        TestDatabaseConnectionResult(
          connected: false,
          latencyMs: 0,
          serverTimeUtc: DateTime.utc(2026),
          error: 'Login failed for user',
        ),
      );

      final message = await provider.testConnection(entry);

      expect(message, 'Login failed for user');
      expect(connectionManager.testRemoteDatabaseConnectionCallCount, 1);
      expect(connectionManager.lastTestConfigId, 'sql-1');
    });

    test('should return transport failure message on socket error', () async {
      const entry = RemoteDatabaseConfigEntry(
        id: 'syb-1',
        name: 'ERP',
        databaseType: RemoteDatabaseType.sybase,
      );
      connectionManager.testConnectionResult = rd.Failure(
        Exception('testRemoteDatabaseConnection timeout'),
      );

      final message = await provider.testConnection(entry);

      expect(message, contains('timeout'));
    });
  });
}
