import 'dart:convert';

import '../../../domain/entities/schedule.dart';

// Classes de configuração para cada tipo de agendamento
class DailyScheduleConfig {
  final int hour;
  final int minute;

  const DailyScheduleConfig({
    required this.hour,
    required this.minute,
  });

  factory DailyScheduleConfig.fromJson(Map<String, dynamic> json) {
    return DailyScheduleConfig(
      hour: json['hour'] as int,
      minute: json['minute'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'hour': hour,
        'minute': minute,
      };
}

class WeeklyScheduleConfig {
  final int hour;
  final int minute;
  final List<int> daysOfWeek; // 1=Monday, 7=Sunday

  const WeeklyScheduleConfig({
    required this.hour,
    required this.minute,
    required this.daysOfWeek,
  });

  factory WeeklyScheduleConfig.fromJson(Map<String, dynamic> json) {
    return WeeklyScheduleConfig(
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      daysOfWeek: (json['daysOfWeek'] as List).cast<int>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'hour': hour,
        'minute': minute,
        'daysOfWeek': daysOfWeek,
      };
}

class MonthlyScheduleConfig {
  final int hour;
  final int minute;
  final List<int> daysOfMonth; // 1-31

  const MonthlyScheduleConfig({
    required this.hour,
    required this.minute,
    required this.daysOfMonth,
  });

  factory MonthlyScheduleConfig.fromJson(Map<String, dynamic> json) {
    return MonthlyScheduleConfig(
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      daysOfMonth: (json['daysOfMonth'] as List).cast<int>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'hour': hour,
        'minute': minute,
        'daysOfMonth': daysOfMonth,
      };
}

class IntervalScheduleConfig {
  final int intervalMinutes;

  const IntervalScheduleConfig({
    required this.intervalMinutes,
  });

  factory IntervalScheduleConfig.fromJson(Map<String, dynamic> json) {
    return IntervalScheduleConfig(
      intervalMinutes: json['intervalMinutes'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'intervalMinutes': intervalMinutes,
      };
}

class ScheduleCalculator {
  /// Calcula a próxima execução baseada no tipo de agendamento
  DateTime? getNextRunTime(Schedule schedule, {DateTime? from}) {
    final now = from ?? DateTime.now();

    switch (schedule.scheduleType) {
      case ScheduleType.daily:
        return _getNextDailyRun(schedule.scheduleConfig, now);
      case ScheduleType.weekly:
        return _getNextWeeklyRun(schedule.scheduleConfig, now);
      case ScheduleType.monthly:
        return _getNextMonthlyRun(schedule.scheduleConfig, now);
      case ScheduleType.interval:
        return _getNextIntervalRun(schedule, now);
    }
  }

  DateTime? _getNextDailyRun(String configJson, DateTime now) {
    try {
      final config = DailyScheduleConfig.fromJson(
        _parseJson(configJson),
      );

      var next = DateTime(
        now.year,
        now.month,
        now.day,
        config.hour,
        config.minute,
      );

      if (next.isBefore(now) || next.isAtSameMomentAs(now)) {
        next = next.add(const Duration(days: 1));
      }

      return next;
    } catch (e) {
      return null;
    }
  }

  DateTime? _getNextWeeklyRun(String configJson, DateTime now) {
    try {
      final config = WeeklyScheduleConfig.fromJson(
        _parseJson(configJson),
      );

      if (config.daysOfWeek.isEmpty) return null;

      // Procurar próximo dia da semana válido
      for (int i = 0; i < 8; i++) {
        final candidate = now.add(Duration(days: i));
        final candidateWeekday = candidate.weekday; // 1=Monday, 7=Sunday

        if (config.daysOfWeek.contains(candidateWeekday)) {
          var next = DateTime(
            candidate.year,
            candidate.month,
            candidate.day,
            config.hour,
            config.minute,
          );

          if (next.isAfter(now)) {
            return next;
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  DateTime? _getNextMonthlyRun(String configJson, DateTime now) {
    try {
      final config = MonthlyScheduleConfig.fromJson(
        _parseJson(configJson),
      );

      if (config.daysOfMonth.isEmpty) return null;

      // Procurar próximo dia do mês válido
      for (int monthOffset = 0; monthOffset < 13; monthOffset++) {
        final targetMonth = DateTime(now.year, now.month + monthOffset, 1);
        final daysInMonth =
            DateTime(targetMonth.year, targetMonth.month + 1, 0).day;

        for (final day in config.daysOfMonth) {
          if (day <= daysInMonth) {
            final candidate = DateTime(
              targetMonth.year,
              targetMonth.month,
              day,
              config.hour,
              config.minute,
            );

            if (candidate.isAfter(now)) {
              return candidate;
            }
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  DateTime? _getNextIntervalRun(Schedule schedule, DateTime now) {
    try {
      final config = IntervalScheduleConfig.fromJson(
        _parseJson(schedule.scheduleConfig),
      );

      // Se nunca executou, executar agora
      if (schedule.lastRunAt == null) {
        return now;
      }

      // Próxima execução = última execução + intervalo
      final next = schedule.lastRunAt!.add(
        Duration(minutes: config.intervalMinutes),
      );

      // Se já passou, executar agora
      if (next.isBefore(now)) {
        return now;
      }

      return next;
    } catch (e) {
      return null;
    }
  }

  Map<String, dynamic> _parseJson(String json) {
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  /// Verifica se um agendamento deve ser executado agora
  bool shouldRunNow(Schedule schedule, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();

    if (!schedule.enabled) return false;
    if (schedule.nextRunAt == null) return false;

    // Calcular diferença entre o horário agendado e o atual
    final diff = schedule.nextRunAt!.difference(currentTime);
    final diffInSeconds = diff.inSeconds;
    
    // Executar apenas se:
    // 1. O horário agendado já passou (diff <= 0) - não executar antes do horário
    // 2. E não passou mais de 1 minuto desde o horário agendado
    // Isso garante que só execute no horário correto ou logo após, evitando execuções antecipadas
    if (diffInSeconds > 0) {
      // Ainda não chegou a hora (horário agendado está no futuro)
      return false;
    }
    
    if (diffInSeconds < -60) {
      // Já passou mais de 1 minuto do horário agendado
      // Não executar para evitar backups muito atrasados
      return false;
    }
    
    // O horário agendado já passou (diff <= 0) e está dentro da janela de 1 minuto
    return true;
  }

  /// Cria uma configuração JSON para agendamento diário
  static String createDailyConfig({
    required int hour,
    required int minute,
  }) {
    return jsonEncode(DailyScheduleConfig(
      hour: hour,
      minute: minute,
    ).toJson());
  }

  /// Cria uma configuração JSON para agendamento semanal
  static String createWeeklyConfig({
    required int hour,
    required int minute,
    required List<int> daysOfWeek,
  }) {
    return jsonEncode(WeeklyScheduleConfig(
      hour: hour,
      minute: minute,
      daysOfWeek: daysOfWeek,
    ).toJson());
  }

  /// Cria uma configuração JSON para agendamento mensal
  static String createMonthlyConfig({
    required int hour,
    required int minute,
    required List<int> daysOfMonth,
  }) {
    return jsonEncode(MonthlyScheduleConfig(
      hour: hour,
      minute: minute,
      daysOfMonth: daysOfMonth,
    ).toJson());
  }

  /// Cria uma configuração JSON para agendamento por intervalo
  static String createIntervalConfig({
    required int intervalMinutes,
  }) {
    return jsonEncode(IntervalScheduleConfig(
      intervalMinutes: intervalMinutes,
    ).toJson());
  }
}

