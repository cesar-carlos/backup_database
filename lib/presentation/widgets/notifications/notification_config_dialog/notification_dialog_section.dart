import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — titled description block wrapping a dialog section.
class NotificationDialogSection extends StatelessWidget {
  const NotificationDialogSection({
    required this.title,
    required this.description,
    required this.child,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.typography.subtitle?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(description, style: theme.typography.caption),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}
