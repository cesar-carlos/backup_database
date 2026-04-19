import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/domain/services/i_backup_cancellation_service.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/presentation/managers/managers.dart';

class AppCleanup {
  AppCleanup._();

  /// Sequência de shutdown da aplicação. Cada etapa é independente e
  /// resiliente a falhas: erros são logados mas não impedem as próximas
  /// (caso contrário, um erro em "fechar tray" deixaria o lock de
  /// instância única vazado, p.ex.).
  ///
  /// Ordem proposital:
  /// 1. Cancelar processos de backup em execução (mata `pg_basebackup`,
  ///    `sqlcmd`, `dbisql` etc. para evitar zumbis após o fechamento).
  /// 2. Parar o scheduler (não aceita mais agendamentos).
  /// 3. Fechar o banco SQLite (faz checkpoint do WAL).
  /// 4. Liberar o mutex de instância única.
  /// 5. Dispose de tray e window managers.
  static Future<void> cleanup() async {
    LoggerService.info('Encerrando aplicativo...');

    await _runStep('cancelar backups em execução', () async {
      if (service_locator.getIt.isRegistered<IBackupCancellationService>()) {
        service_locator.getIt<IBackupCancellationService>().cancelAllRunning();
      }
    });

    await _runStep('parar scheduler', () async {
      if (service_locator.getIt.isRegistered<ISchedulerService>()) {
        service_locator.getIt<ISchedulerService>().stop();
      }
    });

    await _runStep('fechar banco de dados', () async {
      if (service_locator.getIt.isRegistered<AppDatabase>()) {
        await service_locator.getIt<AppDatabase>().close();
      }
    });

    await _runStep('liberar lock de instância única', () async {
      if (service_locator.getIt.isRegistered<ISingleInstanceService>()) {
        await service_locator
            .getIt<ISingleInstanceService>()
            .releaseLock();
      }
    });

    await _runStep('destruir tray', () async => TrayManagerService().dispose());
    await _runStep(
      'destruir window manager',
      () async => WindowManagerService().dispose(),
    );

    LoggerService.info('Aplicativo encerrado');
  }

  /// Executa uma etapa do shutdown isolando falhas. Etapas com [getIt]
  /// não registrado são tratadas como no-op silencioso (cenários de
  /// shutdown precoce, antes do `setupServiceLocator` completar).
  static Future<void> _runStep(String label, Future<void> Function() fn) async {
    try {
      await fn();
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao $label: $e', e, s);
    }
  }
}
