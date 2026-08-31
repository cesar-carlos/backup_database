import 'package:flutter/widgets.dart';

class AppBreakpoints {
  AppBreakpoints._();

  /// Windows at or below this width use compact chrome (800×600 included).
  static const double compact = 900;
  static const double medium = 1024;
  static const double wide = 1440;

  static const Size minimumWindow = Size(800, 600);
  static const Size initialWindow = Size(1280, 800);

  static const double compactPaneWidth = 48;
  static const double expandedPaneWidth = 216;
}

extension AppBreakpointsX on BuildContext {
  bool get isCompactWindow =>
      MediaQuery.sizeOf(this).width < AppBreakpoints.compact;

  bool get isMediumWindow =>
      MediaQuery.sizeOf(this).width < AppBreakpoints.medium;

  bool get isWideWindow =>
      MediaQuery.sizeOf(this).width >= AppBreakpoints.medium;
}
