import 'package:backup_database/presentation/widgets/organisms/app_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

final class _GridRow {
  const _GridRow(this.name, this.status, this.owner);

  final String name;
  final String status;
  final String owner;
}

@widgetbook.UseCase(name: 'Default', type: AppDataGrid)
Widget buildAppDataGridDefaultUseCase(BuildContext context) {
  const rows = [
    _GridRow('Nightly backup', 'Active', 'scheduler'),
    _GridRow('Monthly archive', 'Paused', 'ops'),
  ];

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: AppDataGrid<_GridRow>(
      minWidth: 760,
      columns: [
        AppDataGridColumn<_GridRow>(
          label: 'Name',
          cellBuilder: (context, row) => Text(row.name),
        ),
        AppDataGridColumn<_GridRow>(
          label: 'Status',
          cellBuilder: (context, row) => Text(row.status),
        ),
        AppDataGridColumn<_GridRow>(
          label: 'Owner',
          cellBuilder: (context, row) => Text(row.owner),
        ),
      ],
      actions: [
        AppDataGridAction<_GridRow>(
          icon: FluentIcons.edit,
          tooltip: 'Edit',
          onPressed: (_) {},
        ),
      ],
      rows: rows,
    ),
  );
}
