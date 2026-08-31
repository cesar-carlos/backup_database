import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/core/theme/tokens/app_target_size.dart';
import 'package:flutter/widgets.dart';

enum AppDensity {
  compact(
    spacingMultiplier: 0.75,
    targetSize: AppTargetSize.desktop,
  ),
  comfortable(
    spacingMultiplier: 1,
    targetSize: AppTargetSize.desktop,
  ),
  spacious(
    spacingMultiplier: 1.25,
    targetSize: AppTargetSize.spacious,
  );

  const AppDensity({
    required this.spacingMultiplier,
    required this.targetSize,
  });

  final double spacingMultiplier;
  final double targetSize;

  EdgeInsets get contentPadding {
    if (this == AppDensity.spacious) {
      return AppSpacing.paddingLg;
    }
    return AppSpacing.paddingMd;
  }
}
