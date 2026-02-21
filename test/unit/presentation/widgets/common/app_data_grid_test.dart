import 'package:backup_database/presentation/widgets/common/app_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _RowData {
  const _RowData({required this.name, required this.status});

  final String name;
  final String status;
}

void main() {
  Widget buildHarness(Widget child) {
    return FluentApp(
      home: NavigationView(
        content: ScaffoldPage(
          content: Center(child: child),
        ),
      ),
    );
  }

  group('AppDataGrid', () {
    testWidgets('renders headers and row cells', (tester) async {
      const rows = [
        _RowData(name: 'Base A', status: 'Ativo'),
        _RowData(name: 'Base B', status: 'Inativo'),
      ];

      await tester.pumpWidget(
        buildHarness(
          AppDataGrid<_RowData>(
            minWidth: 600,
            columns: [
              AppDataGridColumn<_RowData>(
                label: 'Nome',
                cellBuilder: (context, row) => Text(row.name),
              ),
              AppDataGridColumn<_RowData>(
                label: 'Status',
                cellBuilder: (context, row) => Text(row.status),
              ),
            ],
            rows: rows,
          ),
        ),
      );

      expect(find.text('Nome'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Base A'), findsOneWidget);
      expect(find.text('Base B'), findsOneWidget);
      expect(find.text('Ativo'), findsOneWidget);
      expect(find.text('Inativo'), findsOneWidget);
    });

    testWidgets('supports horizontal scroll when minWidth exceeds viewport', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildHarness(
          const SizedBox(
            width: 260,
            child: AppDataGrid<_RowData>(
              minWidth: 1200,
              columns: [
                AppDataGridColumn<_RowData>(
                  label: 'Nome',
                  cellBuilder: _nameCell,
                ),
              ],
              rows: [
                _RowData(name: 'Base A', status: 'Ativo'),
              ],
            ),
          ),
        ),
      );

      final horizontalScrollViews = find.byWidgetPredicate((widget) {
        return widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal;
      });

      expect(horizontalScrollViews, findsOneWidget);

      await tester.pumpAndSettle();
      final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(scrollbar.thumbVisibility, isTrue);
    });

    testWidgets('fills available width when viewport is wider than minWidth', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildHarness(
          const SizedBox(
            width: 900,
            child: AppDataGrid<_RowData>(
              minWidth: 600,
              columns: [
                AppDataGridColumn<_RowData>(
                  label: 'Nome',
                  cellBuilder: _nameCell,
                ),
              ],
              rows: [
                _RowData(name: 'Base A', status: 'Ativo'),
              ],
            ),
          ),
        ),
      );

      final tableSize = tester.getSize(find.byType(Table));
      final viewportSize = tester.getSize(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      );
      expect(tableSize.width, closeTo(viewportSize.width, 0.1));
    });

    testWidgets('triggers row action callback', (tester) async {
      _RowData? tapped;

      await tester.pumpWidget(
        buildHarness(
          AppDataGrid<_RowData>(
            columns: [
              AppDataGridColumn<_RowData>(
                label: 'Nome',
                cellBuilder: (context, row) => Text(row.name),
              ),
            ],
            actions: [
              AppDataGridAction<_RowData>(
                icon: FluentIcons.edit,
                tooltip: 'Editar',
                onPressed: (row) {
                  tapped = row;
                },
              ),
            ],
            rows: const [
              _RowData(name: 'Base A', status: 'Ativo'),
            ],
          ),
        ),
      );

      await tester.tap(find.byIcon(FluentIcons.edit));
      await tester.pumpAndSettle();

      expect(tapped, isNotNull);
      expect(tapped!.name, 'Base A');
    });

    testWidgets('disables row action when isEnabled returns false', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildHarness(
          AppDataGrid<_RowData>(
            columns: [
              AppDataGridColumn<_RowData>(
                label: 'Nome',
                cellBuilder: (context, row) => Text(row.name),
              ),
            ],
            actions: [
              AppDataGridAction<_RowData>(
                icon: FluentIcons.delete,
                tooltip: 'Excluir',
                isEnabled: (row) => row.status == 'Ativo',
                onPressed: (_) {},
              ),
            ],
            rows: const [
              _RowData(name: 'Base B', status: 'Inativo'),
            ],
          ),
        ),
      );

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
    });
  });
}

Widget _nameCell(BuildContext context, _RowData row) => Text(row.name);
