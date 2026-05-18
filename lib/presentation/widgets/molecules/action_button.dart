import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — primary action control with optional icon and loading state.
class ActionButton extends StatelessWidget {
  const ActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.isLoading = false,
    this.iconSize,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final Widget child = isLoading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: ProgressRing(strokeWidth: 2),
          )
        : FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  ExcludeSemantics(
                    child: Icon(icon, size: iconSize ?? 16),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(label),
              ],
            ),
          );

    return Semantics(
      button: true,
      label: isLoading ? 'Loading' : label,
      enabled: !isLoading && onPressed != null,
      child: Button(
        onPressed: isLoading ? null : onPressed,
        child: child,
      ),
    );
  }
}
