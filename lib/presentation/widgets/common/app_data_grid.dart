import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

typedef AppDataGridCellBuilder<T> =
    Widget Function(
      BuildContext context,
      T row,
    );

class AppDataGridColumn<T> {
  const AppDataGridColumn({
    required this.label,
    required this.cellBuilder,
    this.width = const FlexColumnWidth(),
    this.headerAlignment = Alignment.centerLeft,
    this.cellAlignment = Alignment.centerLeft,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  });

  final String label;
  final AppDataGridCellBuilder<T> cellBuilder;
  final TableColumnWidth width;
  final AlignmentGeometry headerAlignment;
  final AlignmentGeometry cellAlignment;
  final EdgeInsetsGeometry padding;
}

class AppDataGridAction<T> {
  const AppDataGridAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
    this.isEnabled,
  });

  final IconData icon;
  final String tooltip;
  final void Function(T row) onPressed;
  final Color? iconColor;
  final bool Function(T row)? isEnabled;

  bool enabledFor(T row) => isEnabled?.call(row) ?? true;
}

class AppDataGrid<T> extends StatelessWidget {
  const AppDataGrid({
    required this.columns,
    required this.rows,
    super.key,
    this.actions = const [],
    this.actionsLabel = 'Acoes',
    this.minWidth,
  });

  final List<AppDataGridColumn<T>> columns;
  final List<T> rows;
  final List<AppDataGridAction<T>> actions;
  final String actionsLabel;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final hasActions = actions.isNotEmpty;
    final resources = FluentTheme.of(context).resources;
    final headerStyle =
        FluentTheme.of(context).typography.bodyStrong ??
        const TextStyle(fontWeight: FontWeight.w600);
    final columnWidths = <int, TableColumnWidth>{
      for (var i = 0; i < columns.length; i++) i: columns[i].width,
      if (hasActions)
        columns.length: FixedColumnWidth(
          math.max(88, (actions.length * 40) + 20).toDouble(),
        ),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth ?? 0),
          child: Table(
            border: TableBorder.all(color: resources.cardStrokeColorDefault),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: columnWidths,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: resources.cardStrokeColorDefault.withValues(
                    alpha: 0.2,
                  ),
                ),
                children: [
                  for (final column in columns)
                    _GridCell(
                      alignment: column.headerAlignment,
                      padding: column.padding,
                      child: Text(column.label, style: headerStyle),
                    ),
                  if (hasActions)
                    _GridCell(
                      alignment: Alignment.center,
                      child: Text(actionsLabel, style: headerStyle),
                    ),
                ],
              ),
              for (final row in rows)
                TableRow(
                  children: [
                    for (final column in columns)
                      _GridCell(
                        alignment: column.cellAlignment,
                        padding: column.padding,
                        child: column.cellBuilder(context, row),
                      ),
                    if (hasActions) _buildActionsCell(context, row),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionsCell(BuildContext context, T row) {
    return _GridCell(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            Tooltip(
              message: action.tooltip,
              child: IconButton(
                icon: Icon(action.icon, color: action.iconColor),
                onPressed: action.enabledFor(row)
                    ? () => action.onPressed(row)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.child,
    this.alignment = Alignment.centerLeft,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  });

  final Widget child;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: alignment,
        child: child,
      ),
    );
  }
}
