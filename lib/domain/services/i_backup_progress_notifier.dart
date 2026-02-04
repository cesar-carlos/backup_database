import 'package:backup_database/domain/entities/backup_progress_snapshot.dart';

abstract class IBackupProgressNotifier {
  void addListener(void Function() callback);
  void removeListener(void Function() callback);
  BackupProgressSnapshot? get currentSnapshot;
  void setCurrentBackupName(String name);
  void updateProgress({
    required String step,
    required String message,
    double? progress,
  });
  bool tryStartBackup([String? scheduleName]);
  void completeBackup({String? message, String? backupPath});
  void failBackup(String error);
}
