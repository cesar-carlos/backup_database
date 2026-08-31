import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — wrapping strip of dashboard stat cards for narrow windows.
class DashboardStatsStrip extends StatelessWidget {
  const DashboardStatsStrip({
    required this.children,
    super.key,
    this.preferredCardWidth = 280,
    this.minCardWidth = 160,
  });

  final List<Widget> children;
  final double preferredCardWidth;
  final double minCardWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        const gap = AppSpacing.md;
        final count = children.length;
        if (count == 0 || !maxWidth.isFinite || maxWidth <= 0) {
          return const SizedBox.shrink();
        }

        final preferredRowWidth =
            count * preferredCardWidth + (count - 1) * gap;
        if (maxWidth >= preferredRowWidth) {
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final Widget child in children)
                SizedBox(width: preferredCardWidth, child: child),
            ],
          );
        }

        final columns = ((maxWidth + gap) / (minCardWidth + gap)).floor().clamp(
          1,
          count,
        );
        final cardWidth = (maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final Widget child in children)
              SizedBox(width: cardWidth, child: child),
          ],
        );
      },
    );
  }
}
