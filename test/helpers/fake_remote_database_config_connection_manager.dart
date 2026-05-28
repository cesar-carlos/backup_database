import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:result_dart/result_dart.dart' as rd;

class FakeRemoteDatabaseConfigConnectionManager extends ConnectionManager {
  FakeRemoteDatabaseConfigConnectionManager({
    this.simulateConnected = true,
    this.simulateFirebirdSupported = false,
  }) : super(serverConnectionRepository: null);

  bool simulateConnected;
  bool simulateFirebirdSupported;

  int listRemoteDatabaseConfigsCallCount = 0;
  int testRemoteDatabaseConnectionCallCount = 0;
  int deleteRemoteDatabaseConfigCallCount = 0;

  RemoteDatabaseType? lastListType;
  String? lastTestConfigId;
  RemoteDatabaseType? lastTestType;
  String? lastDeleteConfigId;

  Map<RemoteDatabaseType, rd.Result<DatabaseConfigListResult>>
  listResultsByType = {};

  rd.Result<TestDatabaseConnectionResult>? testConnectionResult;
  rd.Result<DatabaseConfigMutationResult>? deleteConfigResult;

  @override
  bool get isConnected => simulateConnected;

  @override
  bool get isFirebirdSupported => simulateFirebirdSupported;

  @override
  Future<rd.Result<DatabaseConfigListResult>> listRemoteDatabaseConfigs(
    RemoteDatabaseType databaseType,
  ) async {
    listRemoteDatabaseConfigsCallCount++;
    lastListType = databaseType;
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    return listResultsByType[databaseType] ??
        rd.Success(
          DatabaseConfigListResult(
            databaseType: databaseType,
            configs: const <Map<String, dynamic>>[],
            serverTimeUtc: DateTime.utc(2026, 5, 22),
          ),
        );
  }

  @override
  Future<rd.Result<TestDatabaseConnectionResult>> testRemoteDatabaseConnection({
    required RemoteDatabaseType databaseType,
    String? databaseConfigId,
    Map<String, dynamic>? config,
    Duration? timeout,
  }) async {
    testRemoteDatabaseConnectionCallCount++;
    lastTestType = databaseType;
    lastTestConfigId = databaseConfigId;
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    return testConnectionResult ??
        rd.Success(
          TestDatabaseConnectionResult(
            connected: true,
            latencyMs: 12,
            serverTimeUtc: DateTime.utc(2026, 5, 22),
          ),
        );
  }

  @override
  Future<rd.Result<DatabaseConfigMutationResult>> deleteRemoteDatabaseConfig({
    required RemoteDatabaseType databaseType,
    required String configId,
    String? idempotencyKey,
  }) async {
    deleteRemoteDatabaseConfigCallCount++;
    lastDeleteConfigId = configId;
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    return deleteConfigResult ??
        rd.Success(
          DatabaseConfigMutationResult(
            operation: 'deleted',
            databaseType: databaseType,
            configId: configId,
          ),
        );
  }
}
