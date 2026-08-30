import 'package:backup_database/core/theme/theme.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Atom** — labeled metric tile for SMTP test history.
class EmailTestHistoryMetricTile extends StatelessWidget {
  const EmailTestHistoryMetricTile({
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
    final theme = FluentTheme.of(context);
    final borderColor = context.colors.outline.withValues(alpha: 0.22);
    final backgroundColor = context.colors.outline.withValues(alpha: 0.08);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.typography.caption),
          const SizedBox(height: 4),
          Text(value, style: theme.typography.subtitle),
          const SizedBox(height: 4),
          Text(caption, style: theme.typography.caption),
        ],
      ),
    );
  }
}
