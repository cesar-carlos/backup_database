import 'package:backup_database/application/providers/database_connection_test_snapshot.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/extensions/app_semantic_colors.dart';
import 'package:backup_database/core/theme/tokens/app_spacing.dart';
import 'package:backup_database/core/utils/database_type_metadata.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/atoms/app_card.dart';
import 'package:backup_database/presentation/widgets/atoms/app_status_chip.dart';
import 'package:backup_database/presentation/widgets/organisms/app_data_grid.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class DatabaseConfigGridRow {
  const DatabaseConfigGridRow({
    required this.databaseType,
    required this.name,
    required this.serverEndpoint,
    required this.database,
    required this.username,
    required this.id,
    required this.enabled,
    this.lastConnectionTest,
  });

  final DatabaseType databaseType;
  final String name;
  final String serverEndpoint;
  final String database;
  final String username;
  final String id;
  final bool enabled;
  final DatabaseConnectionTestSnapshot? lastConnectionTest;
}

/// **Organism** - shared data grid for database configuration lists.
class DatabaseConfigDataGrid<T extends Object> extends StatelessWidget {
  const DatabaseConfigDataGrid({
    required this.configs,
    required this.rowOf,
    super.key,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onToggleEnabled,
    this.minWidth = 1180,
    this.onAddWhenEmpty,
    this.addWhenEmptyButtonLabel,
    this.emptyStateMessage,
    this.connectionTestSnapshot,
  });

  final List<T> configs;
  final DatabaseConfigGridRow Function(T row) rowOf;
  final void Function(T)? onEdit;
  final void Function(T)? onDuplicate;
  final void Function(String)? onDelete;
  final void Function(String, bool)? onToggleEnabled;
  final double minWidth;
  final VoidCallback? onAddWhenEmpty;
  final String? addWhenEmptyButtonLabel;
  final String? emptyStateMessage;
  final DatabaseConnectionTestSnapshot? Function(String configId)?
  connectionTestSnapshot;

  @override
  Widget build(BuildContext context) {
    if (configs.isEmpty) {
      final addLabel = addWhenEmptyButtonLabel;
      final resolvedEmptyStateMessage =
          emptyStateMessage ??
          appLocaleString(
            context,
            'Nenhuma configuração cadastrada para este tipo.',
            'No configuration registered for this type.',
          );

      if (onAddWhenEmpty != null &&
          addLabel != null &&
          addLabel.trim().isNotEmpty) {
        return AppCard(
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      resolvedEmptyStateMessage,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: onAddWhenEmpty,
                      child: Text(addLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return AppCard(
        child: SizedBox.expand(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                appLocaleString(
                  context,
                  'Nenhuma configuração encontrada',
                  'No configuration found',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    DatabaseConfigGridRow viewFor(T row) {
      final base = rowOf(row);
      final snap = connectionTestSnapshot;
      if (snap == null) {
        return base;
      }
      return DatabaseConfigGridRow(
        databaseType: base.databaseType,
        name: base.name,
        serverEndpoint: base.serverEndpoint,
        database: base.database,
        username: base.username,
        id: base.id,
        enabled: base.enabled,
        lastConnectionTest: snap(base.id),
      );
    }

    final columns = <AppDataGridColumn<T>>[
      AppDataGridColumn<T>(
        label: appLocaleString(context, 'Tipo', 'Type'),
        width: const FlexColumnWidth(1.15),
        cellBuilder: (context, row) => _DatabaseTypeChip(
          type: viewFor(row).databaseType,
        ),
      ),
      AppDataGridColumn<T>(
        label: appLocaleString(context, 'Nome', 'Name'),
        width: const FlexColumnWidth(1.8),
        cellBuilder: (context, row) => Text(viewFor(row).name),
      ),
      AppDataGridColumn<T>(
        label: appLocaleString(context, 'Servidor', 'Server'),
        width: const FlexColumnWidth(1.9),
        cellBuilder: (context, row) => Text(viewFor(row).serverEndpoint),
      ),
      AppDataGridColumn<T>(
        label: appLocaleString(context, 'Banco', 'Database'),
        width: const FlexColumnWidth(1.5),
        cellBuilder: (context, row) => Text(viewFor(row).database),
      ),
      AppDataGridColumn<T>(
        label: appLocaleString(context, 'Usuário', 'User'),
        width: const FlexColumnWidth(1.5),
        cellBuilder: (context, row) => Text(viewFor(row).username),
      ),
    ];

    if (connectionTestSnapshot != null) {
      columns.add(
        AppDataGridColumn<T>(
          label: appLocaleString(
            context,
            'Última verificação',
            'Last check',
          ),
          width: const FlexColumnWidth(1.6),
          cellBuilder: (context, row) {
            final test = viewFor(row).lastConnectionTest;
            if (test == null) {
              return Text(
                appLocaleString(context, 'Nunca', 'Never'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            }
            final fmt = DateFormat.yMd().add_Hm();
            final when = fmt.format(test.testedAt);
            final iconColor = test.success
                ? context.appSemanticColors.success
                : context.appSemanticColors.danger;
            return Tooltip(
              message: test.success
                  ? appLocaleString(
                      context,
                      'Último teste de conexão: OK ($when)',
                      'Last connection test: OK ($when)',
                    )
                  : appLocaleString(
                      context,
                      'Último teste de conexão: falhou ($when)',
                      'Last connection test: failed ($when)',
                    ),
              child: Row(
                children: [
                  Icon(
                    test.success
                        ? FluentIcons.check_mark
                        : FluentIcons.error_badge,
                    size: 16,
                    color: iconColor,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      when,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    columns.add(
      AppDataGridColumn<T>(
        label: appLocaleString(context, 'Status', 'Status'),
        width: const FlexColumnWidth(1.2),
        cellBuilder: (context, row) {
          final view = viewFor(row);
          return Row(
            children: [
              ToggleSwitch(
                checked: view.enabled,
                onChanged: onToggleEnabled != null
                    ? (bool enabled) => onToggleEnabled!(view.id, enabled)
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  view.enabled
                      ? appLocaleString(context, 'Ativo', 'Active')
                      : appLocaleString(context, 'Inativo', 'Inactive'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );

    return AppCard(
      child: SizedBox.expand(
        child: AppDataGrid<T>(
          minWidth: minWidth,
          columns: columns,
          actions: [
            AppDataGridAction<T>(
              icon: FluentIcons.edit,
              tooltip: appLocaleString(context, 'Editar', 'Edit'),
              onPressed: (row) => onEdit?.call(row),
              isEnabled: (_) => onEdit != null,
            ),
            AppDataGridAction<T>(
              icon: FluentIcons.copy,
              tooltip: appLocaleString(context, 'Duplicar', 'Duplicate'),
              onPressed: (row) => onDuplicate?.call(row),
              isEnabled: (_) => onDuplicate != null,
            ),
            AppDataGridAction<T>(
              icon: FluentIcons.delete,
              iconColor: context.colors.danger,
              tooltip: appLocaleString(context, 'Excluir', 'Delete'),
              onPressed: (row) => onDelete?.call(viewFor(row).id),
              isEnabled: (_) => onDelete != null,
            ),
          ],
          rows: configs,
        ),
      ),
    );
  }
}

class _DatabaseTypeChip extends StatelessWidget {
  const _DatabaseTypeChip({
    required this.type,
  });

  final DatabaseType type;

  @override
  Widget build(BuildContext context) {
    final metadata = DatabaseTypeMetadata.of(type);
    return AppStatusChip(
      label: metadata.chipLabel,
      color: metadata.accentColor,
    );
  }
}
