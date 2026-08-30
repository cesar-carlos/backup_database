import 'dart:async';

import 'package:backup_database/application/providers/remote/pending_remote_run_store.dart';
import 'package:flutter/foundation.dart';

class RemoteSchedulesRunSession {
  RemoteSchedulesRunSession({
    required this.notifyListeners,
    required this.pendingRunStore,
  });

  final VoidCallback notifyListeners;
  final PendingRemoteRunStore pendingRunStore;

  bool isExecuting = false;
  bool disconnectedDuringRun = false;
  bool isResumingAfterReconnect = false;
  bool isTransferringFile = false;

  String? executingScheduleId;
  String? activeRunId;
  String? error;
  String? lastErrorCode;
  String? backupStep;
  String? backupMessage;
  double? backupProgress;
  String? transferStep;
  String? transferMessage;
  double? transferProgress;

  static const String connectionLostMessage =
      'Conexão perdida; consultando servidor após reconectar...';

  static const String artifactExpiredMessage =
      'Artefato expirou no servidor; execute um novo backup.';

  void beginExecution(String scheduleId) {
    isExecuting = true;
    executingScheduleId = scheduleId;
    activeRunId = null;
    disconnectedDuringRun = false;
    error = null;
    lastErrorCode = null;
    backupStep = 'Iniciando';
    backupMessage = 'Solicitando backup no servidor...';
    backupProgress = null;
    transferStep = null;
    transferMessage = null;
    transferProgress = null;
    isTransferringFile = false;
    notifyListeners();
  }

  void resetExecutionState({String? error, String? errorCode}) {
    isExecuting = false;
    executingScheduleId = null;
    activeRunId = null;
    disconnectedDuringRun = false;
    backupStep = null;
    backupMessage = null;
    backupProgress = null;
    transferStep = null;
    transferMessage = null;
    transferProgress = null;
    isTransferringFile = false;
    this.error = error;
    lastErrorCode = errorCode;
    unawaited(pendingRunStore.clear());
    notifyListeners();
  }

  void onBackupProgress(String step, String message, double progress) {
    backupStep = step;
    backupMessage = message;
    backupProgress = progress;
    notifyListeners();
  }

  void clearExecutionStateOnDisconnect() {
    if (executingScheduleId == null) return;
    disconnectedDuringRun = activeRunId != null;
    isExecuting = false;
    backupStep = null;
    backupMessage = null;
    backupProgress = null;
    transferStep = null;
    transferMessage = null;
    transferProgress = null;
    isTransferringFile = false;
    error = disconnectedDuringRun
        ? connectionLostMessage
        : 'Conexão perdida durante o backup.';
    lastErrorCode = null;
    notifyListeners();
  }

  void applyRestoredSnapshot(PendingRemoteRunSnapshot snapshot) {
    activeRunId = snapshot.runId;
    executingScheduleId = snapshot.scheduleId;
    disconnectedDuringRun = true;
    backupStep = 'Aguardando reconexão';
    backupMessage =
        'Execução remota pendente detectada do boot anterior; '
        'retomaremos assim que a conexão for restabelecida.';
    notifyListeners();
  }
}
