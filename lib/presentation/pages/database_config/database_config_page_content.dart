part of 'database_config_page.dart';

class _DatabaseConfigsContent extends StatelessWidget {
  const _DatabaseConfigsContent({
    required this.sqlProvider,
    required this.sybaseProvider,
    required this.postgresProvider,
    required this.firebirdProvider,
    required this.hideFirebirdSection,
    required this.onRefresh,
    required this.onCreateConfig,
    required this.onEditSql,
    required this.onDuplicateSql,
    required this.onDeleteSql,
    required this.onToggleSqlEnabled,
    required this.onEditSybase,
    required this.onDuplicateSybase,
    required this.onDeleteSybase,
    required this.onToggleSybaseEnabled,
    required this.onEditPostgres,
    required this.onDuplicatePostgres,
    required this.onDeletePostgres,
    required this.onTogglePostgresEnabled,
    required this.onEditFirebird,
    required this.onDuplicateFirebird,
    required this.onDeleteFirebird,
    required this.onToggleFirebirdEnabled,
  });

  final SqlServerConfigProvider sqlProvider;
  final SybaseConfigProvider sybaseProvider;
  final PostgresConfigProvider postgresProvider;
  final FirebirdConfigProvider firebirdProvider;
  final bool hideFirebirdSection;

  final VoidCallback onRefresh;
  final Future<void> Function() onCreateConfig;

  final Future<void> Function(SqlServerConfig?) onEditSql;
  final Future<void> Function(SqlServerConfig) onDuplicateSql;
  final Future<void> Function(String) onDeleteSql;
  final void Function(String, bool) onToggleSqlEnabled;

  final Future<void> Function(SybaseConfig?) onEditSybase;
  final Future<void> Function(SybaseConfig) onDuplicateSybase;
  final Future<void> Function(String) onDeleteSybase;
  final void Function(String, bool) onToggleSybaseEnabled;

  final Future<void> Function(PostgresConfig?) onEditPostgres;
  final Future<void> Function(PostgresConfig) onDuplicatePostgres;
  final Future<void> Function(String) onDeletePostgres;
  final void Function(String, bool) onTogglePostgresEnabled;

  final Future<void> Function(FirebirdConfig?) onEditFirebird;
  final Future<void> Function(FirebirdConfig) onDuplicateFirebird;
  final Future<void> Function(String) onDeleteFirebird;
  final void Function(String, bool) onToggleFirebirdEnabled;

  @override
  Widget build(BuildContext context) {
    if (sqlProvider.isLoading ||
        sybaseProvider.isLoading ||
        postgresProvider.isLoading ||
        (!hideFirebirdSection && firebirdProvider.isLoading)) {
      return AppPageState.loading(
        title: appLocaleString(
          context,
          'Carregando configurações',
          'Loading database configurations',
        ),
        message: appLocaleString(
          context,
          'Buscando conexões configuradas na aplicação.',
          'Fetching configured database connections.',
        ),
      );
    }

    final errorMessage =
        sqlProvider.error ??
        sybaseProvider.error ??
        postgresProvider.error ??
        (hideFirebirdSection ? null : firebirdProvider.error);
    if (errorMessage != null) {
      return AppPageState.error(
        title: appLocaleString(
          context,
          'Falha ao carregar configurações',
          'Failed to load database configurations',
        ),
        message: errorMessage,
        actionLabel: appLocaleString(context, 'Tentar novamente', 'Try again'),
        onAction: onRefresh,
      );
    }

    final rows = _buildRows();
    if (rows.isEmpty) {
      return AppPageState.empty(
        title: appLocaleString(
          context,
          'Nenhuma configuração cadastrada',
          'No database configuration yet',
        ),
        message: appLocaleString(
          context,
          'Cadastre conexões para usar em backups e agendamentos.',
          'Add connections to use in backups and schedules.',
        ),
        actionLabel: appLocaleString(
          context,
          'Nova configuração',
          'New configuration',
        ),
        onAction: () {
          unawaited(onCreateConfig());
        },
      );
    }

    final activeCount = rows.where((row) => row.enabled).length;
    final inactiveCount = rows.length - activeCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeaderWithStatusBadges(
          label: appLocaleString(
            context,
            'Todas as configurações',
            'All configurations',
          ),
          count: rows.length,
          activeCount: activeCount,
          inactiveCount: inactiveCount,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: DatabaseConfigDataGrid<_DatabaseConfigListRow>(
            configs: rows,
            rowOf: (row) => DatabaseConfigGridRow(
              databaseType: row.databaseType,
              name: row.name,
              serverEndpoint: row.serverEndpoint,
              database: row.database,
              username: row.username,
              id: row.id,
              enabled: row.enabled,
              lastConnectionTest: row.lastConnectionTest,
            ),
            onEdit: (row) => unawaited(row.edit()),
            onDuplicate: (row) => unawaited(row.duplicate()),
            onDelete: (id) => unawaited(_rowById(rows, id).delete()),
            onToggleEnabled: (id, enabled) => _rowById(
              rows,
              id,
            ).toggleEnabled(enabled),
            onAddWhenEmpty: () {
              unawaited(onCreateConfig());
            },
            addWhenEmptyButtonLabel: appLocaleString(
              context,
              'Nova configuração',
              'New configuration',
            ),
            emptyStateMessage: appLocaleString(
              context,
              'Nenhuma configuração cadastrada ainda.',
              'No database configuration yet.',
            ),
            connectionTestSnapshot: (configId) => _rowById(
              rows,
              configId,
            ).lastConnectionTest,
          ),
        ),
      ],
    );
  }

  List<_DatabaseConfigListRow> _buildRows() {
    final rows = <_DatabaseConfigListRow>[
      for (final config in sqlProvider.configs)
        _DatabaseConfigListRow(
          id: config.id,
          databaseType: DatabaseType.sqlServer,
          name: config.name,
          serverEndpoint: '${config.server}:${config.portValue}',
          database: config.databaseValue,
          username: config.username,
          enabled: config.enabled,
          lastConnectionTest: sqlProvider.connectionTestSnapshotFor(config.id),
          edit: () => onEditSql(config),
          duplicate: () => onDuplicateSql(config),
          delete: () => onDeleteSql(config.id),
          toggleEnabled: (enabled) => onToggleSqlEnabled(config.id, enabled),
        ),
      for (final config in sybaseProvider.configs)
        _DatabaseConfigListRow(
          id: config.id,
          databaseType: DatabaseType.sybase,
          name: config.name,
          serverEndpoint: '${config.serverName}:${config.portValue}',
          database: config.databaseNameValue,
          username: config.username,
          enabled: config.enabled,
          lastConnectionTest: sybaseProvider.connectionTestSnapshotFor(
            config.id,
          ),
          edit: () => onEditSybase(config),
          duplicate: () => onDuplicateSybase(config),
          delete: () => onDeleteSybase(config.id),
          toggleEnabled: (enabled) => onToggleSybaseEnabled(config.id, enabled),
        ),
      for (final config in postgresProvider.configs)
        _DatabaseConfigListRow(
          id: config.id,
          databaseType: DatabaseType.postgresql,
          name: config.name,
          serverEndpoint: '${config.host}:${config.portValue}',
          database: config.databaseValue,
          username: config.username,
          enabled: config.enabled,
          lastConnectionTest: postgresProvider.connectionTestSnapshotFor(
            config.id,
          ),
          edit: () => onEditPostgres(config),
          duplicate: () => onDuplicatePostgres(config),
          delete: () => onDeletePostgres(config.id),
          toggleEnabled: (enabled) =>
              onTogglePostgresEnabled(config.id, enabled),
        ),
      if (!hideFirebirdSection)
        for (final config in firebirdProvider.configs)
          _DatabaseConfigListRow(
            id: config.id,
            databaseType: DatabaseType.firebird,
            name: config.name,
            serverEndpoint: '${config.host}:${config.portValue}',
            database: config.databaseFile,
            username: config.username,
            enabled: config.enabled,
            lastConnectionTest: firebirdProvider.connectionTestSnapshotFor(
              config.id,
            ),
            edit: () => onEditFirebird(config),
            duplicate: () => onDuplicateFirebird(config),
            delete: () => onDeleteFirebird(config.id),
            toggleEnabled: (enabled) =>
                onToggleFirebirdEnabled(config.id, enabled),
          ),
    ];

    rows.sort((a, b) {
      if (a.enabled != b.enabled) {
        return a.enabled ? -1 : 1;
      }

      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) {
        return byName;
      }

      return a.databaseType.index.compareTo(b.databaseType.index);
    });

    return rows;
  }

  _DatabaseConfigListRow _rowById(
    List<_DatabaseConfigListRow> rows,
    String id,
  ) {
    return rows.firstWhere((row) => row.id == id);
  }
}

class _DatabaseConfigListRow {
  const _DatabaseConfigListRow({
    required this.id,
    required this.databaseType,
    required this.name,
    required this.serverEndpoint,
    required this.database,
    required this.username,
    required this.enabled,
    required this.edit,
    required this.duplicate,
    required this.delete,
    required this.toggleEnabled,
    this.lastConnectionTest,
  });

  final String id;
  final DatabaseType databaseType;
  final String name;
  final String serverEndpoint;
  final String database;
  final String username;
  final bool enabled;
  final DatabaseConnectionTestSnapshot? lastConnectionTest;
  final Future<void> Function() edit;
  final Future<void> Function() duplicate;
  final Future<void> Function() delete;
  final void Function(bool enabled) toggleEnabled;
}
