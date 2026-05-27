const String scheduleIdArgumentPrefix = '--schedule-id=';

String scheduleIdArgument(String scheduleId) =>
    '$scheduleIdArgumentPrefix$scheduleId';

abstract final class ScheduleArgs {
  static String? extract(List<String> args) {
    for (final arg in args) {
      if (arg.startsWith(scheduleIdArgumentPrefix)) {
        return arg.substring(scheduleIdArgumentPrefix.length);
      }
    }
    return null;
  }

  static bool contains(List<String> args) {
    for (final arg in args) {
      if (arg.startsWith(scheduleIdArgumentPrefix)) {
        return true;
      }
    }
    return false;
  }
}
