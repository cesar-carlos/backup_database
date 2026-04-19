import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_backup_cancellation_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';

/// Implementação de [IBackupCancellationService] que delega para
/// `ProcessService.cancelByTag`.
///
/// Mantém a camada de aplicação independente de `ProcessService`
/// (infrastructure), respeitando a regra de dependências do Clean
/// Architecture.
class BackupCancellationService implements IBackupCancellationService {
  BackupCancellationService(this._processService);

  final ProcessService _processService;

  @override
  void cancelByTag(String tag) {
    if (tag.isEmpty) return;
    LoggerService.info('Solicitação de cancelamento recebida para tag: $tag');
    _processService.cancelByTag(tag);
  }

  @override
  void cancelBySchedule(String scheduleId) =>
      cancelByTag('backup-$scheduleId');

  @override
  void cancelByHistoryId(String historyId) =>
      cancelByTag('backup-$historyId');

  @override
  void cancelAllRunning() {
    final cancelled = _processService.cancelAllRunning();
    if (cancelled > 0) {
      LoggerService.info(
        'Cancelados $cancelled processo(s) de backup em execução durante '
        'shutdown.',
      );
    }
  }
}
