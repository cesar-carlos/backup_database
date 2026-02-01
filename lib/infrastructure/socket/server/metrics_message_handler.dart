import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';

typedef SendToClient = Future<void> Function(String clientId, Message message);

class MetricsMessageHandler {
  MetricsMessageHandler({
    required IBackupHistoryRepository backupHistoryRepository,
    required IScheduleRepository scheduleRepository,
  })  : _backupHistoryRepository = backupHistoryRepository,
        _scheduleRepository = scheduleRepository;

  final IBackupHistoryRepository _backupHistoryRepository;
  final IScheduleRepository _scheduleRepository;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isMetricsRequestMessage(message)) return;

    final requestId = message.header.requestId;

    try {
      final payload = await _buildMetricsPayload();
      await sendToClient(
        clientId,
        createMetricsResponseMessage(
          requestId: requestId,
          payload: payload,
        ),
      );
    } on Object catch (e) {
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: e.toString(),
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _buildMetricsPayload() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    var totalBackups = 0;
    var backupsToday = 0;
    var failedToday = 0;
    var activeSchedules = 0;
    var recentBackups = <Map<String, dynamic>>[];

    final allResult = await _backupHistoryRepository.getAll(limit: 1000);
    allResult.fold(
      (list) => totalBackups = list.length,
      (_) {},
    );

    final todayResult = await _backupHistoryRepository.getByDateRange(
      startOfDay,
      endOfDay,
    );
    todayResult.fold(
      (list) {
        backupsToday = list.length;
        failedToday =
            list.where((b) => b.status == BackupStatus.error).length;
      },
      (_) {},
    );

    final schedulesResult = await _scheduleRepository.getEnabled();
    schedulesResult.fold(
      (list) => activeSchedules = list.length,
      (_) {},
    );

    final recentResult = await _backupHistoryRepository.getAll(limit: 10);
    recentResult.fold(
      (list) {
        recentBackups = list.map(_backupHistoryToMap).toList();
      },
      (_) {},
    );

    final payload = <String, dynamic>{
      'totalBackups': totalBackups,
      'backupsToday': backupsToday,
      'failedToday': failedToday,
      'activeSchedules': activeSchedules,
      'recentBackups': recentBackups,
    };
    return payload;
  }

  Map<String, dynamic> _backupHistoryToMap(BackupHistory h) {
    return <String, dynamic>{
      'id': h.id,
      'scheduleId': h.scheduleId,
      'databaseName': h.databaseName,
      'databaseType': h.databaseType,
      'backupPath': h.backupPath,
      'fileSize': h.fileSize,
      'status': h.status.name,
      'startedAt': h.startedAt.toIso8601String(),
      'finishedAt': h.finishedAt?.toIso8601String(),
      'errorMessage': h.errorMessage,
    };
  }
}
