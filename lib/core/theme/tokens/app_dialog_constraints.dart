import 'dart:math' as math;

import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:flutter/widgets.dart';

class AppDialogConstraints {
  AppDialogConstraints._();

  static const double preferredWidth = 560;
  static const double maxHeightFraction = 0.9;
  static const double chromeReserve = 96;

  static double maxHeightOf(BuildContext context) {
    return MediaQuery.sizeOf(context).height * maxHeightFraction;
  }

  static BoxConstraints of(
    BuildContext context, {
    double preferredWidth = preferredWidth,
  }) {
    final size = MediaQuery.sizeOf(context);
    final double maxWidth = math.min(
      preferredWidth,
      math.max(0, size.width - AppSpacing.xl),
    );
    return BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: size.height * maxHeightFraction,
    );
  }

  static BoxConstraints bodyOf(BuildContext context) {
    return BoxConstraints(
      maxHeight: math.max(
        0,
        maxHeightOf(context) - chromeReserve,
      ),
    );
  }
}
