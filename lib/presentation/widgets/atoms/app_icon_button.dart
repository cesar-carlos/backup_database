import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — icon-only control with tooltip and semantics.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.label,
    required this.icon,
    super.key,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final targetSize = InheritedAppDensity.resolve(context).targetSize;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        enabled: onPressed != null,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: targetSize,
              minHeight: targetSize,
            ),
            child: IconButton(
              iconButtonMode: IconButtonMode.small,
              icon: Icon(icon),
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}
