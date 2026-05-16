import 'package:flutter/widgets.dart';

class AppBreakpoints {
  AppBreakpoints._();

  static const double compact = 720;
  static const double medium = 1024;
  static const double wide = 1440;
}

extension AppBreakpointsX on BuildContext {
  bool get isCompactWindow =>
      MediaQuery.sizeOf(this).width < AppBreakpoints.compact;

  bool get isMediumWindow =>
      MediaQuery.sizeOf(this).width < AppBreakpoints.medium;

  bool get isWideWindow =>
      MediaQuery.sizeOf(this).width >= AppBreakpoints.medium;
}
