import 'package:backup_database/core/theme/theme.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — card surface using design-system padding, radius, and depth.
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
    final shadowColor = context.colors.onSurface.withValues(alpha: 0.08);
    final Widget card = Card(
      padding: padding ?? AppSpacing.paddingMd,
      margin: EdgeInsets.zero,
      borderRadius: AppRadius.circularLg,
      child: child,
    );

    final elevated = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: AppRadius.circularLg,
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: AppElevation.low * 2,
            offset: const Offset(0, AppElevation.low),
          ),
        ],
      ),
      child: card,
    );

    final tappable = onTap != null
        ? Semantics(
            button: true,
            child: GestureDetector(
              onTap: onTap,
              child: elevated,
            ),
          )
        : elevated;

    return tappable;
  }
}
