import 'dart:async';

import 'package:backup_database/application/providers/remote_schedules_provider.dart'
    show RemoteSchedulesProvider;
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_status_messages.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/protocol/queue_events.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Connection manager configurável para testes de [RemoteSchedulesProvider].
class FakeRemoteSchedulesConnectionManager extends ConnectionManager {
  FakeRemoteSchedulesConnectionManager({
    this.simulateConnected = true,
    this.simulateRunIdSupported = true,
    this.simulateQueueSupported = false,
    this.simulateArtifactRetentionSupported = false,
  }) : super(serverConnectionRepository: null);

  bool simulateConnected;
  bool simulateRunIdSupported;
  bool simulateQueueSupported;
  bool simulateArtifactRetentionSupported;

  int executeRemoteBackupCallCount = 0;
  int executeScheduleCallCount = 0;
  int validatePreflightCallCount = 0;
  int getExecutionStatusCallCount = 0;
  int attachListenerCallCount = 0;
  int waitForCompletionCallCount = 0;
  int getExecutionQueueCallCount = 0;
  int getServerHealthCallCount = 0;
  int getServerSessionCallCount = 0;
  int cancelQueuedRemoteBackupCallCount = 0;
  int createRemoteScheduleCallCount = 0;
  int deleteRemoteScheduleCallCount = 0;
  int pauseRemoteScheduleCallCount = 0;
  int resumeRemoteScheduleCallCount = 0;

  Schedule? lastCreateSchedulePayload;
  String? lastMutationScheduleId;

  rd.Result<ScheduleMutationResult>? createRemoteScheduleResult;
  rd.Result<ScheduleMutationResult>? deleteRemoteScheduleResult;
  rd.Result<ScheduleMutationResult>? pauseRemoteScheduleResult;
  rd.Result<ScheduleMutationResult>? resumeRemoteScheduleResult;

  String? lastScheduleId;
  String? lastRunIdForCancelQueued;
  String? lastRunIdForCancel;
  String? notifiedRunId;
  void Function(String runId)? lastOnRunIdKnown;

  rd.Result<PreflightResult> preflightResult = rd.Success(
    PreflightResult(
      status: PreflightStatus.passed,
      checks: const [],
      serverTimeUtc: DateTime.utc(2026),
    ),
  );

  rd.Result<String> remoteBackupResult = const rd.Success('');

  Completer<rd.Result<String>>? remoteBackupCompleter;

  ExecutionStatusResult? executionStatusToReturn;
  rd.Result<String>? waitForCompletionResult;
  rd.Result<ArtifactMetadataResult>? artifactMetadataResult;

  rd.Result<List<Schedule>> listSchedulesResult = const rd.Success(
    <Schedule>[],
  );
  rd.Result<ExecutionQueueResult> executionQueueResult = rd.Success(
    ExecutionQueueResult(
      queue: const <QueuedExecution>[],
      totalQueued: 0,
      maxQueueSize: 50,
      serverTimeUtc: DateTime.utc(2026),
    ),
  );
  rd.Result<CancelQueuedBackupResult>? cancelQueuedBackupResult;

  rd.Result<ServerHealth> serverHealthResult = rd.Success(
    ServerHealth(
      status: ServerHealthStatus.ok,
      checks: const <String, bool>{},
      serverTimeUtc: DateTime.utc(2026, 5, 22),
      uptimeSeconds: 3600,
    ),
  );

  rd.Result<ServerSession> serverSessionResult = rd.Success(
    ServerSession(
      clientId: 'test-client',
      isAuthenticated: true,
      host: '127.0.0.1',
      port: 9000,
      connectedAt: DateTime.utc(2026, 5, 22),
      serverTimeUtc: DateTime.utc(2026, 5, 22),
    ),
  );

  @override
  bool get isConnected => simulateConnected;

  @override
  Stream<QueueEvent> get queueEvents => const Stream<QueueEvent>.empty();

  @override
  bool get isRunIdSupported => simulateRunIdSupported;

  @override
  bool get isExecutionQueueSupported => simulateQueueSupported;

  @override
  bool get isArtifactRetentionSupported => simulateArtifactRetentionSupported;

  @override
  Future<rd.Result<List<Schedule>>> listSchedules() async {
    return listSchedulesResult;
  }

  @override
  Future<rd.Result<ScheduleMutationResult>> createRemoteSchedule({
    required Schedule schedule,
    String? idempotencyKey,
  }) async {
    createRemoteScheduleCallCount++;
    lastCreateSchedulePayload = schedule;
    return createRemoteScheduleResult ??
        rd.Success(
          ScheduleMutationResult(
            operation: 'created',
            scheduleId: schedule.id,
            schedule: schedule,
          ),
        );
  }

  @override
  Future<rd.Result<ScheduleMutationResult>> deleteRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) async {
    deleteRemoteScheduleCallCount++;
    lastMutationScheduleId = scheduleId;
    return deleteRemoteScheduleResult ??
        rd.Success(
          ScheduleMutationResult(
            operation: 'deleted',
            scheduleId: scheduleId,
          ),
        );
  }

  @override
  Future<rd.Result<ScheduleMutationResult>> pauseRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) async {
    pauseRemoteScheduleCallCount++;
    lastMutationScheduleId = scheduleId;
    return pauseRemoteScheduleResult ??
        rd.Success(
          ScheduleMutationResult(
            operation: 'paused',
            scheduleId: scheduleId,
          ),
        );
  }

  @override
  Future<rd.Result<ScheduleMutationResult>> resumeRemoteSchedule({
    required String scheduleId,
    String? idempotencyKey,
  }) async {
    resumeRemoteScheduleCallCount++;
    lastMutationScheduleId = scheduleId;
    return resumeRemoteScheduleResult ??
        rd.Success(
          ScheduleMutationResult(
            operation: 'resumed',
            scheduleId: scheduleId,
          ),
        );
  }

  @override
  Future<rd.Result<ExecutionQueueResult>> getExecutionQueue() async {
    getExecutionQueueCallCount++;
    return executionQueueResult;
  }

  @override
  Future<rd.Result<ServerHealth>> getServerHealth() async {
    getServerHealthCallCount++;
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    return serverHealthResult;
  }

  @override
  Future<rd.Result<ServerSession>> getServerSession() async {
    getServerSessionCallCount++;
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    return serverSessionResult;
  }

  @override
  Future<rd.Result<CancelQueuedBackupResult>> cancelQueuedRemoteBackup({
    required String runId,
    String? idempotencyKey,
  }) async {
    cancelQueuedRemoteBackupCallCount++;
    lastRunIdForCancelQueued = runId;
    return cancelQueuedBackupResult ??
        rd.Success(
          CancelQueuedBackupResult(
            state: ExecutionState.cancelled,
            runId: runId,
            serverTimeUtc: DateTime.utc(2026),
          ),
        );
  }

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
            serverTimeUtc: DateTime.utc(2026),
            stagingPath: 'remote/run-test/backup.zip',
          ),
        );
  }

  @override
  Future<void> disconnect() async {}

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
        serverTimeUtc: DateTime.utc(2026),
      ),
    );
  }
}
