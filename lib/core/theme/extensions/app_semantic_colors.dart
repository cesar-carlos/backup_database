import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.outline,
    required this.divider,
    required this.disabled,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color surface;
  final Color surfaceVariant;
  final Color onSurface;
  final Color outline;
  final Color divider;
  final Color disabled;

  static const AppSemanticColors light = AppSemanticColors(
    success: Color(0xFF2E7D32),
    warning: Color(0xFFE65100),
    danger: Color(0xFFC62828),
    info: Color(0xFF1565C0),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF5F5F5),
    onSurface: Color(0xFF212121),
    outline: Color(0xFF9E9E9E),
    divider: Color(0xFFE0E0E0),
    disabled: Color(0xFF9E9E9E),
  );

  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF81C784),
    warning: Color(0xFFFFB74D),
    danger: Color(0xFFEF5350),
    info: Color(0xFF64B5F6),
    surface: Color(0xFF1E1E1E),
    surfaceVariant: Color(0xFF2C2C2C),
    onSurface: Color(0xFFE0E0E0),
    outline: Color(0xFF757575),
    divider: Color(0xFF424242),
    disabled: Color(0xFF757575),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? surface,
    Color? surfaceVariant,
    Color? onSurface,
    Color? outline,
    Color? divider,
    Color? disabled,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      onSurface: onSurface ?? this.onSurface,
      outline: outline ?? this.outline,
      divider: divider ?? this.divider,
      disabled: disabled ?? this.disabled,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) {
      return this;
    }
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
    );
  }
}

extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get colors => appSemanticColors;

  AppSemanticColors get appSemanticColors {
    final fluent = FluentTheme.maybeOf(this);
    if (fluent != null) {
      return fluent.extension<AppSemanticColors>() ?? AppSemanticColors.light;
    }
    try {
      final material = Theme.of(this);
      return material.extension<AppSemanticColors>() ?? AppSemanticColors.light;
    } on Object {
      return AppSemanticColors.light;
    }
  }
}
