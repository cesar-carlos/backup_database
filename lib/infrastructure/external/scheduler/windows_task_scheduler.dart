import 'dart:io';
import 'dart:convert';

import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/schedule.dart';
import 'cron_parser.dart' as parser;

class WindowsTaskSchedulerService {
  /// Cria uma tarefa no Windows Task Scheduler
  Future<rd.Result<bool>> createTask({
    required Schedule schedule,
    required String executablePath,
  }) async {
    try {
      LoggerService.info(
        'Criando tarefa no Windows Task Scheduler: ${schedule.name}',
      );

      final taskName = 'BackupDatabase_${schedule.id}';

      // Deletar tarefa existente se houver
      await _deleteTask(taskName);

      // Construir comando schtasks
      final arguments = <String>[
        '/Create',
        '/TN',
        taskName,
        '/TR',
        '"$executablePath" --schedule-id=${schedule.id}',
        '/SC',
        _getScheduleType(schedule),
        ..._getScheduleArguments(schedule),
        '/F', // Forçar criação
      ];

      final result = await Process.run(
        'schtasks',
        arguments,
        runInShell: true,
      );

      if (result.exitCode == 0) {
        LoggerService.info('Tarefa criada com sucesso: $taskName');
        return const rd.Success(true);
      } else {
        return rd.Failure(
          ServerFailure(
            message: 'Erro ao criar tarefa: ${result.stderr}',
          ),
        );
      }
    } catch (e, stackTrace) {
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
  Future<rd.Result<bool>> deleteTask(String scheduleId) async {
    try {
      final taskName = 'BackupDatabase_$scheduleId';
      await _deleteTask(taskName);
      return const rd.Success(true);
    } catch (e) {
      return rd.Failure(
        ServerFailure(message: 'Erro ao remover tarefa: $e'),
      );
    }
  }

  Future<void> _deleteTask(String taskName) async {
    await Process.run(
      'schtasks',
      ['/Delete', '/TN', taskName, '/F'],
      runInShell: true,
    );
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
      final configJson = jsonDecode(schedule.scheduleConfig);

      switch (schedule.scheduleType) {
        case ScheduleType.daily:
          final config = parser.DailyScheduleConfig.fromJson(configJson);
          args.addAll([
            '/ST',
            '${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}',
          ]);
          break;

        case ScheduleType.weekly:
          final config = parser.WeeklyScheduleConfig.fromJson(configJson);
          final days = config.daysOfWeek.map(_weekdayToString).join(',');
          args.addAll(['/D', days]);
          args.addAll([
            '/ST',
            '${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}',
          ]);
          break;

        case ScheduleType.monthly:
          final config = parser.MonthlyScheduleConfig.fromJson(configJson);
          final days = config.daysOfMonth.join(',');
          args.addAll(['/D', days]);
          args.addAll([
            '/ST',
            '${config.hour.toString().padLeft(2, '0')}:${config.minute.toString().padLeft(2, '0')}',
          ]);
          break;

        case ScheduleType.interval:
          final config = parser.IntervalScheduleConfig.fromJson(configJson);
          args.addAll(['/MO', config.intervalMinutes.toString()]);
          break;
      }
    } catch (e) {
      LoggerService.error('Erro ao parse de config de agendamento', e);
    }

    return args;
  }

  String _weekdayToString(int weekday) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[weekday - 1];
  }
}

