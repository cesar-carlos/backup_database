import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — responsive column grid for history metric tiles.
class EmailTestHistoryMetricGrid extends StatelessWidget {
  const EmailTestHistoryMetricGrid({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= AppBreakpoints.wide => 4,
          >= AppBreakpoints.compact => 2,
          _ => 1,
        };

        if (columns == 1) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index < children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final end = (start + columns) > children.length
              ? children.length
              : start + columns;
          final rowChildren = children.sublist(start, end);

          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < rowChildren.length; index++) ...[
                    Expanded(child: rowChildren[index]),
                    if (index < rowChildren.length - 1)
                      const SizedBox(width: 12),
                  ],
                  for (
                    var filler = rowChildren.length;
                    filler < columns;
                    filler++
                  ) ...[
                    if (filler > 0) const SizedBox(width: 12),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              rows[index],
              if (index < rows.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
