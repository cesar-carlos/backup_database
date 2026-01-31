import 'package:backup_database/domain/entities/schedule.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Interface abstrata para serviços de agendamento de tarefas do sistema
/// operacional.
///
/// Permite diferentes implementações (Windows Task Scheduler, cron, etc.)
/// seguindo o princípio de Dependency Inversion (DIP).
/// A implementação concreta é injetada via service locator.
abstract class ITaskSchedulerService {
  Future<rd.Result<bool>> createTask({
    required Schedule schedule,
    required String executablePath,
  });

  Future<rd.Result<bool>> deleteTask(String scheduleId);
}
