part of 'database_config_page.dart';

mixin _DatabaseConfigPageActions on State<DatabaseConfigPage> {
  Future<void> _showNewConfigDialog() async {
    var hideFirebirdOption = false;
    if (currentAppMode == AppMode.client) {
      try {
        final scp = context.read<ServerConnectionProvider>();
        hideFirebirdOption = scp.isConnected && !scp.isFirebirdSupported;
      } on ProviderNotFoundException {
        hideFirebirdOption = false;
      }
    }

    final kind = await showDialog<DatabaseType>(
      context: context,
      builder: (BuildContext dialogContext) {
        return ContentDialog(
          title: Text(
            appLocaleString(
              context,
              'Tipo de banco de dados',
              'Database type',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  child: Text(
                    DatabaseTypeMetadata.of(DatabaseType.sqlServer).titleLabel,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(
                    DatabaseType.sqlServer,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  child: Text(
                    DatabaseTypeMetadata.of(DatabaseType.sybase).titleLabel,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(
                    DatabaseType.sybase,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  child: Text(
                    DatabaseTypeMetadata.of(DatabaseType.postgresql).titleLabel,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(
                    DatabaseType.postgresql,
                  ),
                ),
                const SizedBox(height: 8),
                if (!hideFirebirdOption) ...[
                  FilledButton(
                    child: Text(
                      DatabaseTypeMetadata.of(DatabaseType.firebird).titleLabel,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(
                      DatabaseType.firebird,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            CancelButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
    if (!mounted || kind == null) {
      return;
    }
    switch (kind) {
      case DatabaseType.sqlServer:
        await _showConfigDialog(null);
      case DatabaseType.sybase:
        await _showSybaseConfigDialog(null);
      case DatabaseType.postgresql:
        await _showPostgresConfigDialog(null);
      case DatabaseType.firebird:
        await _showFirebirdConfigDialog(null);
    }
  }

  Future<void> _duplicateSqlServerConfig(SqlServerConfig config) async {
    final newName = await _promptDuplicateConfigurationName(
      config.name,
    );
    if (newName == null || !mounted) {
      return;
    }

    final provider = context.read<SqlServerConfigProvider>();
    final duplicate = provider
        .duplicateConfigCopy(config)
        .copyWith(name: newName);
    final success = await provider.createConfig(duplicate);

    if (!mounted) return;

    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Configuração duplicada com sucesso!',
            'Configuration duplicated successfully!',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              provider.error ??
              appLocaleString(
                context,
                'Erro ao duplicar configuração',
                'Error duplicating configuration',
              ),
        ),
      );
    }
  }

  Future<void> _duplicateSybaseConfig(SybaseConfig config) async {
    final newName = await _promptDuplicateConfigurationName(
      config.name,
    );
    if (newName == null || !mounted) {
      return;
    }

    final provider = context.read<SybaseConfigProvider>();
    final duplicate = provider
        .duplicateConfigCopy(config)
        .copyWith(name: newName);
    final success = await provider.createConfig(duplicate);

    if (!mounted) return;

    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Configuração duplicada com sucesso!',
            'Configuration duplicated successfully!',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              provider.error ??
              appLocaleString(
                context,
                'Erro ao duplicar configuração Sybase',
                'Error duplicating Sybase configuration',
              ),
        ),
      );
    }
  }

  Future<void> _showConfigDialog(SqlServerConfig? config) async {
    final result = await SqlServerConfigDialog.show(
      context,
      config: config,
    );

    if (result == null || !mounted) {
      return;
    }

    final sqlServerProvider = context.read<SqlServerConfigProvider>();
    final success = config == null
        ? await sqlServerProvider.createConfig(result)
        : await sqlServerProvider.updateConfig(result);
    final errorMessage = sqlServerProvider.error;

    if (!mounted) {
      return;
    }

    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: config == null
              ? appLocaleString(
                  context,
                  'Configuração criada com sucesso!',
                  'Configuration created successfully!',
                )
              : appLocaleString(
                  context,
                  'Configuração atualizada com sucesso!',
                  'Configuration updated successfully!',
                ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              errorMessage ??
              appLocaleString(
                context,
                'Erro ao salvar configuração',
                'Error saving configuration',
              ),
        ),
      );
    }
  }

  Future<void> _showSybaseConfigDialog(SybaseConfig? config) async {
    final result = await SybaseConfigDialog.show(
      context,
      config: config,
      backupService: GetIt.instance<ISybaseBackupService>(),
    );

    if (result != null && mounted) {
      final sybaseProvider = context.read<SybaseConfigProvider>();
      final success = config == null
          ? await sybaseProvider.createConfig(result)
          : await sybaseProvider.updateConfig(result);

      if (!mounted) return;

      if (success) {
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: config == null
                ? appLocaleString(
                    context,
                    'Configuração Sybase criada com sucesso!',
                    'Sybase configuration created successfully!',
                  )
                : appLocaleString(
                    context,
                    'Configuração Sybase atualizada com sucesso!',
                    'Sybase configuration updated successfully!',
                  ),
          ),
        );
      } else {
        unawaited(
          MessageModal.showError(
            context,
            message:
                sybaseProvider.error ??
                appLocaleString(
                  context,
                  'Erro ao salvar configuração Sybase',
                  'Error saving Sybase configuration',
                ),
          ),
        );
      }
    }
  }

  Future<void> _showPostgresConfigDialog(PostgresConfig? config) async {
    final result = await PostgresConfigDialog.show(
      context,
      config: config,
    );

    if (result != null && mounted) {
      final postgresProvider = context.read<PostgresConfigProvider>();
      final success = config == null
          ? await postgresProvider.createConfig(result)
          : await postgresProvider.updateConfig(result);

      if (!mounted) return;

      if (success) {
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: config == null
                ? appLocaleString(
                    context,
                    'Configuração PostgreSQL criada com sucesso!',
                    'PostgreSQL configuration created successfully!',
                  )
                : appLocaleString(
                    context,
                    'Configuração PostgreSQL atualizada com sucesso!',
                    'PostgreSQL configuration updated successfully!',
                  ),
          ),
        );
      } else {
        unawaited(
          MessageModal.showError(
            context,
            message:
                postgresProvider.error ??
                appLocaleString(
                  context,
                  'Erro ao salvar configuração PostgreSQL',
                  'Error saving PostgreSQL configuration',
                ),
          ),
        );
      }
    }
  }

  Future<void> _duplicatePostgresConfig(PostgresConfig config) async {
    final newName = await _promptDuplicateConfigurationName(
      config.name,
    );
    if (newName == null || !mounted) {
      return;
    }

    final provider = context.read<PostgresConfigProvider>();
    final duplicate = provider
        .duplicateConfigCopy(config)
        .copyWith(name: newName);
    final success = await provider.createConfig(duplicate);

    if (!mounted) return;

    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Configuração duplicada com sucesso!',
            'Configuration duplicated successfully!',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              provider.error ??
              appLocaleString(
                context,
                'Erro ao duplicar configuração PostgreSQL',
                'Error duplicating PostgreSQL configuration',
              ),
        ),
      );
    }
  }

  Future<void> _confirmDeletePostgres(String id) async {
    final provider = context.read<PostgresConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ??
        appLocaleString(
          context,
          'Configuração PostgreSQL',
          'PostgreSQL configuration',
        );

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: DatabaseTypeMetadata.of(
        DatabaseType.postgresql,
      ).titleLabel,
      confirmMessage: appLocaleString(
        context,
        'Tem certeza que deseja excluir esta configuração?',
        'Are you sure you want to delete this configuration?',
      ),
      successMessage: appLocaleString(
        context,
        'Configuração PostgreSQL excluída com sucesso!',
        'PostgreSQL configuration deleted successfully!',
      ),
      fallbackErrorMessage: appLocaleString(
        context,
        'Erro ao excluir configuração PostgreSQL',
        'Error deleting PostgreSQL configuration',
      ),
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _showFirebirdConfigDialog(FirebirdConfig? config) async {
    final result = await FirebirdConfigDialog.show(
      context,
      config: config,
    );

    if (result != null && mounted) {
      final provider = context.read<FirebirdConfigProvider>();
      final success = config == null
          ? await provider.createConfig(result)
          : await provider.updateConfig(result);

      if (!mounted) {
        return;
      }

      if (success) {
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: config == null
                ? appLocaleString(
                    context,
                    'Configuração Firebird criada com sucesso!',
                    'Firebird configuration created successfully!',
                  )
                : appLocaleString(
                    context,
                    'Configuração Firebird atualizada com sucesso!',
                    'Firebird configuration updated successfully!',
                  ),
          ),
        );
      } else {
        unawaited(
          MessageModal.showError(
            context,
            message:
                provider.error ??
                appLocaleString(
                  context,
                  'Erro ao salvar configuração Firebird',
                  'Error saving Firebird configuration',
                ),
          ),
        );
      }
    }
  }

  Future<void> _duplicateFirebirdConfig(FirebirdConfig config) async {
    final newName = await _promptDuplicateConfigurationName(
      config.name,
    );
    if (newName == null || !mounted) {
      return;
    }

    final provider = context.read<FirebirdConfigProvider>();
    final duplicate = provider
        .duplicateConfigCopy(config)
        .copyWith(name: newName);
    final success = await provider.createConfig(duplicate);

    if (!mounted) {
      return;
    }

    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Configuração duplicada com sucesso!',
            'Configuration duplicated successfully!',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message:
              provider.error ??
              appLocaleString(
                context,
                'Erro ao duplicar configuração Firebird',
                'Error duplicating Firebird configuration',
              ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteFirebird(String id) async {
    final provider = context.read<FirebirdConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ??
        appLocaleString(
          context,
          'Configuração Firebird',
          'Firebird configuration',
        );

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: DatabaseTypeMetadata.of(DatabaseType.firebird).titleLabel,
      confirmMessage: appLocaleString(
        context,
        'Tem certeza que deseja excluir esta configuração?',
        'Are you sure you want to delete this configuration?',
      ),
      successMessage: appLocaleString(
        context,
        'Configuração Firebird excluída com sucesso!',
        'Firebird configuration deleted successfully!',
      ),
      fallbackErrorMessage: appLocaleString(
        context,
        'Erro ao excluir configuração Firebird',
        'Error deleting Firebird configuration',
      ),
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _confirmDeleteSqlServer(String id) async {
    final provider = context.read<SqlServerConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ??
        appLocaleString(
          context,
          'Configuração SQL Server',
          'SQL Server configuration',
        );

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: DatabaseTypeMetadata.of(DatabaseType.sqlServer).titleLabel,
      confirmMessage: appLocaleString(
        context,
        'Tem certeza que deseja excluir esta configuração?',
        'Are you sure you want to delete this configuration?',
      ),
      successMessage: appLocaleString(
        context,
        'Configuração SQL Server excluída com sucesso!',
        'SQL Server configuration deleted successfully!',
      ),
      fallbackErrorMessage: appLocaleString(
        context,
        'Erro ao excluir configuração SQL Server',
        'Error deleting SQL Server configuration',
      ),
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _confirmDeleteSybase(String id) async {
    final provider = context.read<SybaseConfigProvider>();
    final configName =
        provider.getConfigById(id)?.name ??
        appLocaleString(context, 'Configuração Sybase', 'Sybase configuration');

    await _handleDeleteWithDependencies(
      configId: id,
      configName: configName,
      databaseLabel: DatabaseTypeMetadata.of(DatabaseType.sybase).titleLabel,
      confirmMessage: appLocaleString(
        context,
        'Tem certeza que deseja excluir esta configuração?',
        'Are you sure you want to delete this configuration?',
      ),
      successMessage: appLocaleString(
        context,
        'Configuração Sybase excluída com sucesso!',
        'Sybase configuration deleted successfully!',
      ),
      fallbackErrorMessage: appLocaleString(
        context,
        'Erro ao excluir configuração Sybase',
        'Error deleting Sybase configuration',
      ),
      onDelete: () => provider.deleteConfig(id),
      readError: () => provider.error,
    );
  }

  Future<void> _handleDeleteWithDependencies({
    required String configId,
    required String configName,
    required String databaseLabel,
    required String confirmMessage,
    required String successMessage,
    required String fallbackErrorMessage,
    required Future<bool> Function() onDelete,
    required String? Function() readError,
  }) async {
    final linkedSchedules = await context
        .read<SchedulerProvider>()
        .getSchedulesByDatabaseConfig(configId);

    if (!mounted) return;

    if (linkedSchedules == null) {
      await MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'Não foi possível validar dependências da configuração. '
              'Tente novamente.',
          'Could not validate configuration dependencies. Please try again.',
        ),
      );
      return;
    }

    if (linkedSchedules.isNotEmpty) {
      final action = await DatabaseConfigDependencyDialog.show(
        context,
        databaseLabel: databaseLabel,
        configName: configName,
        schedules: linkedSchedules,
      );

      if (!mounted) return;

      if (action == DependencyDialogAction.goToSchedules) {
        context.go(RouteNames.schedules);
      }
      return;
    }

    final confirmed = await _confirmDeleteConfiguration(confirmMessage);

    if (!confirmed || !mounted) return;

    final success = await onDelete();

    if (!mounted) return;

    if (success) {
      await FluentInfoBarFeedback.showSuccess(context, message: successMessage);
      return;
    }

    await MessageModal.showError(
      context,
      message: readError() ?? fallbackErrorMessage,
    );
  }

  Future<bool> _confirmDeleteConfiguration(String message) {
    return MessageModal.showConfirm(
      context,
      title: appLocaleString(context, 'Confirmar exclusão', 'Confirm deletion'),
      message: message,
      confirmLabel: appLocaleString(context, 'Excluir', 'Delete'),
      confirmIcon: FluentIcons.delete,
    );
  }

  Future<String?> _promptDuplicateConfigurationName(String sourceName) {
    final initial = '$sourceName (cópia)';
    return MessageModal.showInputConfirm(
      context,
      title: appLocaleString(
        context,
        'Duplicar configuração',
        'Duplicate configuration',
      ),
      message: appLocaleString(
        context,
        'Informe o nome da nova configuração.',
        'Enter a name for the new configuration.',
      ),
      fieldLabel: appLocaleString(
        context,
        'Nome da nova configuração',
        'New configuration name',
      ),
      initialValue: initial,
      confirmLabel: appLocaleString(context, 'Duplicar', 'Duplicate'),
      confirmIcon: FluentIcons.copy,
    );
  }
}
