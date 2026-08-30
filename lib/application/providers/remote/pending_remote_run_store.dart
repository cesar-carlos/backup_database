import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';

class PendingRemoteRunSnapshot {
  const PendingRemoteRunSnapshot({
    required this.runId,
    required this.scheduleId,
  });

  final String runId;
  final String scheduleId;
}

class PendingRemoteRunStore {
  PendingRemoteRunStore(this._settings);

  final IMachineSettingsRepository? _settings;

  Future<void> persist({
    required String runId,
    required String scheduleId,
  }) async {
    final settings = _settings;
    if (settings == null) return;
    try {
      final json = jsonEncode({
        'v': 1,
        'runId': runId,
        'scheduleId': scheduleId,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await settings.setPendingRemoteRunSnapshotJson(json);
    } on Object catch (e, s) {
      LoggerService.warning(
        '[remote_schedules] Falha ao persistir snapshot de run pendente: $e',
        e,
        s,
      );
    }
  }

  Future<void> clear() async {
    final settings = _settings;
    if (settings == null) return;
    try {
      await settings.setPendingRemoteRunSnapshotJson(null);
    } on Object catch (e, s) {
      LoggerService.warning(
        '[remote_schedules] Falha ao limpar snapshot de run pendente: $e',
        e,
        s,
      );
    }
  }

  Future<PendingRemoteRunSnapshot?> restore() async {
    final settings = _settings;
    if (settings == null) return null;
    try {
      final raw = await settings.getPendingRemoteRunSnapshotJson();
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final runId = decoded['runId'] as String?;
      final scheduleId = decoded['scheduleId'] as String?;
      if (runId == null || runId.isEmpty) return null;
      if (scheduleId == null || scheduleId.isEmpty) return null;
      return PendingRemoteRunSnapshot(runId: runId, scheduleId: scheduleId);
    } on Object catch (e, s) {
      LoggerService.warning(
        '[remote_schedules] Falha ao restaurar snapshot pré-restart: $e',
        e,
        s,
      );
      return null;
    }
  }
}
