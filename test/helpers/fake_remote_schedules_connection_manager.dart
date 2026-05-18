import 'dart:async';

import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Connection manager configurável para testes de [RemoteSchedulesProvider].
class FakeRemoteSchedulesConnectionManager extends ConnectionManager {
  FakeRemoteSchedulesConnectionManager({
    this.simulateConnected = true,
    this.simulateRunIdSupported = true,
    this.simulateQueueSupported = false,
  }) : super(serverConnectionDao: null);

  bool simulateConnected;
  bool simulateRunIdSupported;
  bool simulateQueueSupported;

  int executeRemoteBackupCallCount = 0;
  int executeScheduleCallCount = 0;
  int validatePreflightCallCount = 0;
  int getExecutionStatusCallCount = 0;
  int attachListenerCallCount = 0;
  int waitForCompletionCallCount = 0;

  String? lastScheduleId;
  String? lastRunIdForCancel;
  String? notifiedRunId;
  void Function(String runId)? lastOnRunIdKnown;

  rd.Result<PreflightResult> preflightResult = rd.Success(
    PreflightResult(
      status: PreflightStatus.passed,
      checks: const [],
      serverTimeUtc: DateTime.utc(2026, 1, 1),
    ),
  );

  rd.Result<String> remoteBackupResult = const rd.Success('');

  Completer<rd.Result<String>>? remoteBackupCompleter;

  ExecutionStatusResult? executionStatusToReturn;
  rd.Result<String>? waitForCompletionResult;
  rd.Result<ArtifactMetadataResult>? artifactMetadataResult;

  @override
  bool get isConnected => simulateConnected;

  @override
  bool get isRunIdSupported => simulateRunIdSupported;

  @override
  bool get isExecutionQueueSupported => simulateQueueSupported;

  @override
  Future<rd.Result<PreflightResult>> validateServerBackupPrerequisites() async {
    validatePreflightCallCount++;
    return preflightResult;
  }

  @override
  Future<rd.Result<String>> executeRemoteBackup({
    required String scheduleId,
    String? idempotencyKey,
    bool queueIfBusy = false,
    BackupProgressCallback? onProgress,
    void Function(String runId)? onRunIdKnown,
  }) async {
    executeRemoteBackupCallCount++;
    lastScheduleId = scheduleId;
    lastOnRunIdKnown = onRunIdKnown;
    notifiedRunId = '${scheduleId}_run-test';
    onRunIdKnown?.call(notifiedRunId!);
    onProgress?.call('Backup', 'progresso', 0.5);
    if (remoteBackupCompleter != null) {
      return remoteBackupCompleter!.future;
    }
    return remoteBackupResult;
  }

  @override
  Future<rd.Result<String>> executeSchedule(
    String scheduleId, {
    BackupProgressCallback? onProgress,
  }) async {
    executeScheduleCallCount++;
    lastScheduleId = scheduleId;
    onProgress?.call('Backup', 'legado', 0.1);
    return remoteBackupResult;
  }

  @override
  Future<rd.Result<ExecutionStatusResult>> getExecutionStatus(
    String runId,
  ) async {
    getExecutionStatusCallCount++;
    final status = executionStatusToReturn;
    if (status == null) {
      return rd.Failure(Exception('status not configured'));
    }
    return rd.Success(status);
  }

  @override
  void attachRemoteBackupListener({
    required String runId,
    required BackupProgressCallback? onProgress,
  }) {
    attachListenerCallCount++;
    lastRunIdForCancel = runId;
  }

  @override
  Future<rd.Result<String>> waitForRemoteBackupCompletion(String runId) async {
    waitForCompletionCallCount++;
    return waitForCompletionResult ??
        const rd.Success('remote/run-test/backup.zip');
  }

  @override
  Future<rd.Result<ArtifactMetadataResult>> getArtifactMetadata({
    required String runId,
  }) async {
    return artifactMetadataResult ??
        rd.Success(
          ArtifactMetadataResult(
            runId: runId,
            found: true,
            serverTimeUtc: DateTime.utc(2026, 1, 1),
            stagingPath: 'remote/run-test/backup.zip',
          ),
        );
  }

  @override
  Future<rd.Result<CancelBackupResult>> cancelRemoteBackup({
    String? runId,
    String? scheduleId,
    String? idempotencyKey,
  }) async {
    lastRunIdForCancel = runId;
    return rd.Success(
      CancelBackupResult(
        runId: runId ?? 'run',
        state: ExecutionState.cancelled,
        scheduleId: scheduleId ?? 'sch',
        serverTimeUtc: DateTime.utc(2026, 1, 1),
      ),
    );
  }
}
