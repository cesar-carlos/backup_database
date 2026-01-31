import 'package:fluent_ui/fluent_ui.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    super.key,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isPrimary = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Button(
        onPressed: null,
        child: SizedBox(
          width: 20,
          height: 20,
          child: ProgressRing(strokeWidth: 2),
        ),
      );
    }

    if (icon != null) {
      return isPrimary
          ? Button(
              onPressed: onPressed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
            )
          : Button(
              onPressed: onPressed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
            );
    }

    return Button(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
