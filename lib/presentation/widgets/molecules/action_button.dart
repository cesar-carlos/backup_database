import 'package:backup_database/presentation/widgets/atoms/app_button.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _actionIconSize = 16;

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
    return AppButton(
      label: label,
      onPressed: onPressed,
      isLoading: isLoading,
      leading: icon == null
          ? null
          : Icon(icon, size: iconSize ?? _actionIconSize),
    );
  }
}
