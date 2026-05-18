import 'dart:math' as math;

import 'package:backup_database/core/theme/tokens/app_radius.dart';
import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:fluent_ui/fluent_ui.dart';

const double _kAppDataGridActionSlotWidth = 44;
const double _kAppDataGridActionsPadding = 16;
const double _kAppDataGridActionsMinWidth = 120;

typedef AppDataGridCellBuilder<T> =
    Widget Function(BuildContext context, T row);

/// **Organism** — scrollable data grid with configurable columns and row actions.
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

class AppDataGrid<T> extends StatefulWidget {
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
  State<AppDataGrid<T>> createState() => _AppDataGridState<T>();
}

class _AppDataGridState<T> extends State<AppDataGrid<T>> {
  late final ScrollController _horizontalScrollController;
  bool _hasHorizontalOverflow = false;

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncOverflowFromController();
    });
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _syncOverflowFromController() {
    if (!_horizontalScrollController.hasClients) {
      return;
    }

    final hasOverflow =
        _horizontalScrollController.position.maxScrollExtent > 0;
    if (_hasHorizontalOverflow == hasOverflow) {
      return;
    }

    setState(() {
      _hasHorizontalOverflow = hasOverflow;
    });
  }

  bool _onScrollMetricsNotification(ScrollMetricsNotification notification) {
    if (notification.metrics.axis == Axis.horizontal) {
      final hasOverflow = notification.metrics.maxScrollExtent > 0;
      if (_hasHorizontalOverflow != hasOverflow) {
        setState(() {
          _hasHorizontalOverflow = hasOverflow;
        });
      }
    }
    return false;
  }

  EdgeInsets _scaledColumnPadding(
    BuildContext context,
    AppDataGridColumn<T> column,
    double densityMultiplier,
  ) {
    final resolved = column.padding.resolve(Directionality.of(context));
    return EdgeInsets.fromLTRB(
      resolved.left * densityMultiplier,
      resolved.top * densityMultiplier,
      resolved.right * densityMultiplier,
      resolved.bottom * densityMultiplier,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final densityMultiplier = InheritedAppDensity.resolve(
          context,
        ).spacingMultiplier;
        final hasActions = widget.actions.isNotEmpty;
        final theme = FluentTheme.of(context);
        final resources = theme.resources;
        final headerStyle =
            theme.typography.bodyStrong ??
            const TextStyle(fontWeight: FontWeight.w600);
        final actionSlotWidth =
            _kAppDataGridActionSlotWidth * densityMultiplier;
        final actionsPadding = _kAppDataGridActionsPadding * densityMultiplier;
        final actionsMinWidth =
            _kAppDataGridActionsMinWidth * densityMultiplier;
        final columnWidths = <int, TableColumnWidth>{
          for (var i = 0; i < widget.columns.length; i++)
            i: widget.columns[i].width,
          if (hasActions)
            widget.columns.length: FixedColumnWidth(
              math.max(
                actionsMinWidth,
                widget.actions.length * actionSlotWidth + actionsPadding,
              ),
            ),
        };
        final viewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final resolvedMinWidth = math.max(
          widget.minWidth ?? 0.0,
          viewportWidth,
        );

        return NotificationListener<ScrollMetricsNotification>(
          onNotification: _onScrollMetricsNotification,
          child: ClipRRect(
            borderRadius: AppRadius.circularMd,
            child: RawScrollbar(
              controller: _horizontalScrollController,
              thumbVisibility: _hasHorizontalOverflow,
              trackVisibility: _hasHorizontalOverflow,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              radius: const Radius.circular(4),
              thickness: 9,
              minThumbLength: 48,
              thumbColor: theme.accentColor.withValues(alpha: 0.9),
              trackColor: resources.controlStrokeColorDefault.withValues(
                alpha: 0.25,
              ),
              trackBorderColor: resources.cardStrokeColorDefault.withValues(
                alpha: 0.45,
              ),
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: resolvedMinWidth),
                  child: Table(
                    border: TableBorder.all(
                      color: resources.cardStrokeColorDefault,
                    ),
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
                          for (final column in widget.columns)
                            _GridCell(
                              alignment: column.headerAlignment,
                              padding: _scaledColumnPadding(
                                context,
                                column,
                                densityMultiplier,
                              ),
                              child: Text(column.label, style: headerStyle),
                            ),
                          if (hasActions)
                            _GridCell(
                              alignment: Alignment.center,
                              padding: EdgeInsets.symmetric(
                                horizontal: 12 * densityMultiplier,
                                vertical: 10 * densityMultiplier,
                              ),
                              child: Text(
                                widget.actionsLabel,
                                style: headerStyle,
                              ),
                            ),
                        ],
                      ),
                      for (final row in widget.rows)
                        TableRow(
                          children: [
                            for (final column in widget.columns)
                              _GridCell(
                                alignment: column.cellAlignment,
                                padding: _scaledColumnPadding(
                                  context,
                                  column,
                                  densityMultiplier,
                                ),
                                child: column.cellBuilder(context, row),
                              ),
                            if (hasActions)
                              _buildActionsCell(
                                context,
                                row,
                                densityMultiplier,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionsCell(
    BuildContext context,
    T row,
    double densityMultiplier,
  ) {
    return _GridCell(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: 12 * densityMultiplier,
        vertical: 10 * densityMultiplier,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in widget.actions)
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
