import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

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
    final Widget card = Card(
      padding: padding ?? AppSpacing.paddingMd,
      margin: margin,
      borderRadius: AppRadius.circularLg,
      child: child,
    );

    if (onTap == null) {
      return card;
    }

    return HoverButton(
      onPressed: onTap,
      cursor: SystemMouseCursors.click,
      builder: (BuildContext context, Set<WidgetState> _) {
        return card;
      },
    );
  }
}
