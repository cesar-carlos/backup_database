import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/i_task_scheduler_service.dart';
import 'package:backup_database/infrastructure/external/scheduler/cron_parser.dart'
    as parser;
import 'package:result_dart/result_dart.dart' as rd;

/// Serviço para gerenciar tarefas agendadas no Windows Task Scheduler.
///
/// Usa `schtasks.exe` (linha de comando) ao invés da API COM do Windows
/// para garantir compatibilidade com Windows Server 2012 R2 e versões mais antigas.
/// A API COM requer Windows 10+ / Server 2016+, enquanto schtasks está disponível
/// desde Windows XP e funciona em todas as versões suportadas.
class WindowsTaskSchedulerService implements ITaskSchedulerService {
  /// Cria uma tarefa no Windows Task Scheduler
  @override
  Future<rd.Result<bool>> createTask({
    required Schedule schedule,
    required String executablePath,
  }) async {
    try {
      LoggerService.info(
        'Criando tarefa no Windows Task Scheduler: ${schedule.name}',
      );

      // Usar prefixo consistente para facilitar identificação e limpeza
      final taskName = 'BackupDatabase_${schedule.id}';

      LoggerService.info(
        'Preparando criação de tarefa: $taskName (Schedule ID: ${schedule.id})',
      );

      // Deletar tarefa existente se houver (necessário para atualizar configuração)
      LoggerService.debug(
        'Verificando e removendo tarefa existente se houver...',
      );
      await _deleteTask(taskName);

      // Construir comando schtasks
      final scheduleType = _getScheduleType(schedule);
      final scheduleArgs = _getScheduleArguments(schedule);
      final arguments = <String>[
        '/Create',
        '/TN',
        taskName,
        '/TR',
        '"$executablePath" --schedule-id=${schedule.id}',
        '/SC',
        scheduleType,
        ...scheduleArgs,
        '/F', // Forçar criação
      ];

      LoggerService.debug(
        'Executando comando schtasks: schtasks ${arguments.join(' ')}',
      );
      LoggerService.debug(
        'Tipo de agendamento: $scheduleType, Configuração: ${schedule.scheduleConfig}',
      );

      final result = await Process.run('schtasks', arguments, runInShell: true);

      if (result.exitCode == 0) {
        LoggerService.info(
          'Tarefa criada com sucesso: $taskName (Schedule: ${schedule.name})',
        );
        if (result.stdout.toString().isNotEmpty) {
          LoggerService.debug('Saída do comando: ${result.stdout}');
        }
        return const rd.Success(true);
      } else {
        LoggerService.error(
          'Falha ao criar tarefa: $taskName',
          Exception('Exit code: ${result.exitCode}'),
        );
        LoggerService.error(
          'Erro do schtasks: ${result.stderr}',
          Exception(result.stderr.toString()),
        );
        if (result.stdout.toString().isNotEmpty) {
          LoggerService.debug('Saída do comando: ${result.stdout}');
        }
        return rd.Failure(
          ServerFailure(message: 'Erro ao criar tarefa: ${result.stderr}'),
        );
      }
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao criar tarefa', e, stackTrace);
      return rd.Failure(
        ServerFailure(
          message: 'Erro ao criar tarefa no Windows Task Scheduler: $e',
          originalError: e,
        ),
      );
    }
  }

  /// Remove uma tarefa do Windows Task Scheduler
  @override
  Future<rd.Result<bool>> deleteTask(String scheduleId) async {
    try {
      final taskName = 'BackupDatabase_$scheduleId';
      LoggerService.info(
        'Removendo tarefa do Windows Task Scheduler: $taskName (Schedule ID: $scheduleId)',
      );
      await _deleteTask(taskName);
      LoggerService.info('Tarefa removida com sucesso: $taskName');
      return const rd.Success(true);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao remover tarefa do Windows Task Scheduler (Schedule ID: $scheduleId)',
        e,
        stackTrace,
      );
      return rd.Failure(ServerFailure(message: 'Erro ao remover tarefa: $e'));
    }
  }

  Future<void> _deleteTask(String taskName) async {
    LoggerService.debug('Executando: schtasks /Delete /TN $taskName /F');
    final result = await Process.run('schtasks', [
      '/Delete',
      '/TN',
      taskName,
      '/F',
    ], runInShell: true);

    if (result.exitCode != 0) {
      // Tarefa pode não existir, apenas logar como debug
      LoggerService.debug(
        'Tarefa não encontrada ou já removida: $taskName (Exit code: ${result.exitCode})',
      );
      if (result.stderr.toString().isNotEmpty) {
        LoggerService.debug('Mensagem: ${result.stderr}');
      }
    } else {
      LoggerService.debug('Tarefa deletada: $taskName');
      if (result.stdout.toString().isNotEmpty) {
        LoggerService.debug('Saída: ${result.stdout}');
      }
    }
  }

  String _getScheduleType(Schedule schedule) {
    switch (schedule.scheduleType) {
      case ScheduleType.daily:
        return 'DAILY';
      case ScheduleType.weekly:
        return 'WEEKLY';
      case ScheduleType.monthly:
        return 'MONTHLY';
      case ScheduleType.interval:
        return 'MINUTE';
    }
  }

  List<String> _getScheduleArguments(Schedule schedule) {
    final args = <String>[];

    try {
      final configJson =
          jsonDecode(schedule.scheduleConfig) as Map<String, dynamic>;

      switch (schedule.scheduleType) {
        case ScheduleType.daily:
          final config = parser.DailyScheduleConfig.fromJson(configJson);
          args.addAll([
            '/ST',
            '${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}',
          ]);

        case ScheduleType.weekly:
          final config = parser.WeeklyScheduleConfig.fromJson(configJson);
          final days = config.daysOfWeek.map(_weekdayToString).join(',');
          args.addAll(['/D', days]);
          args.addAll([
            '/ST',
            '${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}',
          ]);

        case ScheduleType.monthly:
          final config = parser.MonthlyScheduleConfig.fromJson(configJson);
          final days = config.daysOfMonth.join(',');
          args.addAll(['/D', days]);
          args.addAll([
            '/ST',
            '${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}',
          ]);

        case ScheduleType.interval:
          final config = parser.IntervalScheduleConfig.fromJson(configJson);
          args.addAll(['/MO', config.intervalMinutes.toString()]);
      }
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao parse de config de agendamento (Schedule ID: ${schedule.id}, Tipo: ${schedule.scheduleType}, Config: ${schedule.scheduleConfig})',
        e,
        stackTrace,
      );
    }

    LoggerService.debug('Argumentos de agendamento gerados: ${args.join(' ')}');
    return args;
  }

  String _weekdayToString(int weekday) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[weekday - 1];
  }
}
