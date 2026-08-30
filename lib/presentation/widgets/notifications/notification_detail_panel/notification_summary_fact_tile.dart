import 'package:backup_database/core/theme/theme.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — labeled value tile used in the notification summary grid.
class NotificationSummaryFactTile extends StatelessWidget {
  const NotificationSummaryFactTile({
    required this.label,
    required this.value,
    required this.caption,
    super.key,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final captionStyle = FluentTheme.of(context).typography.caption;
    final outline = context.colors.outline;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: outline.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outline.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: captionStyle),
          const SizedBox(height: 4),
          Text(value, style: FluentTheme.of(context).typography.subtitle),
          const SizedBox(height: 4),
          Text(caption, style: captionStyle),
        ],
      ),
    );
  }
}
