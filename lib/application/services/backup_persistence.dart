import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:result_dart/result_dart.dart';

class BackupPersistence {
  BackupPersistence({
    required IBackupHistoryRepository backupHistoryRepository,
    required IBackupLogRepository backupLogRepository,
  }) : _backupHistoryRepository = backupHistoryRepository,
       _backupLogRepository = backupLogRepository;

  final IBackupHistoryRepository _backupHistoryRepository;
  final IBackupLogRepository _backupLogRepository;

  Future<Result<BackupHistory>> createHistory(BackupHistory history) async {
    return _backupHistoryRepository.create(history);
  }

  Future<Result<BackupLog>> createLog(BackupLog log) async {
    return _backupLogRepository.create(log);
  }

  Future<Result<void>> updateHistory(BackupHistory history) async {
    return _backupHistoryRepository.update(history);
  }
}
