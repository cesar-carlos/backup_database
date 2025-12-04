import 'package:fluent_ui/fluent_ui.dart';

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isPrimary;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isPrimary = true,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Button(
        onPressed: null,
        child: const SizedBox(
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
