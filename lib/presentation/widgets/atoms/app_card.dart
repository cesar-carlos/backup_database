import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _hoverOverlayAlpha = 0.08;
const double _pressedOverlayAlpha = 0.16;

/// **Atom** — flat card surface using design-system padding and radius.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding,
    this.margin,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return _AppCardSurface(
        padding: padding,
        margin: margin,
        child: child,
      );
    }

    return Semantics(
      button: true,
      child: HoverButton(
        onPressed: onTap,
        cursor: SystemMouseCursors.click,
        builder: (BuildContext context, Set<WidgetState> states) {
          return _AppCardSurface(
            padding: padding,
            margin: margin,
            states: states,
            child: child,
          );
        },
      ),
    );
  }
}

class _AppCardSurface extends StatelessWidget {
  const _AppCardSurface({
    required this.child,
    this.padding,
    this.margin,
    this.states = const <WidgetState>{},
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Set<WidgetState> states;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isHovered = states.contains(WidgetState.hovered);
    final isPressed = states.contains(WidgetState.pressed);
    final isFocused = states.contains(WidgetState.focused);

    final double overlayAlpha;
    if (isPressed) {
      overlayAlpha = _pressedOverlayAlpha;
    } else if (isHovered || isFocused) {
      overlayAlpha = _hoverOverlayAlpha;
    } else {
      overlayAlpha = 0;
    }

    final Color? backgroundColor = overlayAlpha == 0
        ? null
        : Color.alphaBlend(
            context.colors.outline.withValues(alpha: overlayAlpha),
            theme.cardColor,
          );

    return Card(
      padding: padding ?? AppSpacing.paddingMd,
      margin: margin,
      borderRadius: AppRadius.circularLg,
      backgroundColor: backgroundColor,
      borderColor: isFocused
          ? theme.accentColor.defaultBrushFor(theme.brightness)
          : null,
      child: child,
    );
  }
}
