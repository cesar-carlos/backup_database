import 'package:backup_database/domain/entities/backup_progress_snapshot.dart';

abstract class IBackupProgressNotifier {
  void addListener(void Function() callback);
  void removeListener(void Function() callback);
  BackupProgressSnapshot? get currentSnapshot;
  void setCurrentBackupName(String name);

  /// Define o identificador do `BackupHistory` em execução. Usado pela UI
  /// para invocar cancelamento granular via
  /// `IBackupCancellationService.cancelByHistoryId`.
  void setCurrentHistoryId(String historyId);
  void updateProgress({
    required String step,
    required String message,
    double? progress,
  });
  bool tryStartBackup([String? scheduleName]);
  void completeBackup({String? message, String? backupPath});
  void failBackup(String error);

  /// PR-6: terminacao por cancelamento explicito (operador via
  /// `cancelBackup` ou watchdog). Distingue de `failBackup` para que o
  /// `ScheduleMessageHandler` emita `backupCancelled` separado.
  /// Implementacoes padrao podem delegar para `failBackup(reason)`
  /// quando nao implementarem o evento dedicado.
  void cancelBackup(String reason);
}
