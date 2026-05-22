class DailyScheduleConfig {
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
  final int hour;
  final int minute;

  Map<String, dynamic> toJson() => {
    'hour': hour,
    'minute': minute,
  };
}

class WeeklyScheduleConfig {
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
  final int hour;
  final int minute;
  final List<int> daysOfWeek;

  Map<String, dynamic> toJson() => {
    'hour': hour,
    'minute': minute,
    'daysOfWeek': daysOfWeek,
  };
}

class MonthlyScheduleConfig {
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
  final int hour;
  final int minute;
  final List<int> daysOfMonth;

  Map<String, dynamic> toJson() => {
    'hour': hour,
    'minute': minute,
    'daysOfMonth': daysOfMonth,
  };
}

class IntervalScheduleConfig {
  const IntervalScheduleConfig({
    required this.intervalMinutes,
  });

  factory IntervalScheduleConfig.fromJson(Map<String, dynamic> json) {
    return IntervalScheduleConfig(
      intervalMinutes: json['intervalMinutes'] as int,
    );
  }
  final int intervalMinutes;

  Map<String, dynamic> toJson() => {
    'intervalMinutes': intervalMinutes,
  };
}
