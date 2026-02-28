import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/core/constants/app_constants.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ServiceSettingsTab extends StatefulWidget {
  const ServiceSettingsTab({super.key});

  @override
  State<ServiceSettingsTab> createState() => _ServiceSettingsTabState();
}

class _ServiceSettingsTabState extends State<ServiceSettingsTab> {
  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WindowsServiceProvider>().checkStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WindowsServiceProvider>(
      builder: (context, provider, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _t('Serviço do Windows', 'Windows Service'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Instale o aplicativo como serviço do Windows para executar backups automaticamente, mesmo sem usuário logado.',
                  'Install the app as a Windows service to run backups automatically, even with no logged-in user.',
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: FluentTheme.of(context).typography.body?.color,
                ),
              ),
              const SizedBox(height: 32),
              if (_shouldShowUacInfoBar(provider)) ...[
                InfoBar(
                  title: Text(
                    _t(
                      'Aguardando confirmação do Administrador (UAC)',
                      'Waiting for Administrator confirmation (UAC)',
                    ),
                  ),
                  content: Text(
                    _getUacInfoBarMessage(provider),
                  ),
                  severity: InfoBarSeverity.warning,
                  isLong: true,
                ),
                const SizedBox(height: 24),
              ],
              _buildStatusCard(context, provider),
              const SizedBox(height: 24),
              if (provider.error != null) ...[
                _buildErrorCard(context, provider),
                const SizedBox(height: 24),
              ],
              _buildActionsCard(context, provider),
              const SizedBox(height: 24),
              _buildInfoCard(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    WindowsServiceProvider provider,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('Status do serviço', 'Service status'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: _t('Estado', 'State'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(provider),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getStatusText(provider),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            if (provider.status?.serviceName != null) ...[
              const SizedBox(height: 12),
              Text(
                '${_t('Nome', 'Name')}: ${provider.status!.serviceName}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    BuildContext context,
    WindowsServiceProvider provider,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(FluentIcons.error_badge, color: Colors.red, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    provider.error!,
                    style: TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: provider.isLoading ? null : () => provider.checkStatus(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.refresh, size: 16),
                  const SizedBox(width: 8),
                  Text(_t('Atualizar status', 'Refresh status')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(
    BuildContext context,
    WindowsServiceProvider provider,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('Ações', 'Actions'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!provider.isInstalled)
                  FilledButton(
                    onPressed: provider.isLoading
                        ? null
                        : () => _installService(context, provider),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.download, size: 16),
                        const SizedBox(width: 8),
                        Text(_t('Instalar serviço', 'Install service')),
                      ],
                    ),
                  ),
                if (provider.isInstalled) ...[
                  FilledButton(
                    onPressed: provider.isLoading
                        ? null
                        : () => _uninstallService(context, provider),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.delete, size: 16),
                        const SizedBox(width: 8),
                        Text(_t('Remover serviço', 'Remove service')),
                      ],
                    ),
                  ),
                  if (provider.isRunning) ...[
                    Button(
                      onPressed: provider.isLoading
                          ? null
                          : () => _stopService(context, provider),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.stop, size: 16),
                          const SizedBox(width: 8),
                          Text(_t('Parar', 'Stop')),
                        ],
                      ),
                    ),
                    Button(
                      onPressed: provider.isLoading
                          ? null
                          : () => _restartService(context, provider),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.sync, size: 16),
                          const SizedBox(width: 8),
                          Text(_t('Reiniciar', 'Restart')),
                        ],
                      ),
                    ),
                  ] else
                    Button(
                      onPressed: provider.isLoading
                          ? null
                          : () => _startService(context, provider),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(FluentIcons.play, size: 16),
                          const SizedBox(width: 8),
                          Text(_t('Iniciar', 'Start')),
                        ],
                      ),
                    ),
                ],
                Button(
                  onPressed: provider.isLoading
                      ? null
                      : () => provider.checkStatus(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.refresh, size: 16),
                      const SizedBox(width: 8),
                      Text(_t('Atualizar status', 'Refresh status')),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('Informações', 'Information'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildInfoItem(
              context,
              _t('Funciona sem usuário logado', 'Works without logged-in user'),
              _t(
                'O serviço executará backups mesmo quando nenhum usuário estiver conectado.',
                'The service will run backups even when no user is logged in.',
              ),
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              context,
              _t('Inicialização automática', 'Automatic startup'),
              _t(
                'O serviço iniciará automaticamente com o Windows.',
                'The service will start automatically with Windows.',
              ),
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              context,
              _t('Logs', 'Logs'),
              '${_t('Os logs são salvos em', 'Logs are saved at')}: '
              '${AppConstants.windowsServiceLogPath}\\',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    BuildContext context,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(FluentIcons.info, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(description, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(WindowsServiceProvider provider) {
    if (provider.isLoading) return Colors.grey;
    if (provider.isInstalled) {
      return provider.isRunning ? Colors.green : Colors.orange;
    }
    return Colors.grey;
  }

  String _getStatusText(WindowsServiceProvider provider) {
    if (provider.isLoading) {
      return switch (provider.operation) {
        WindowsServiceOperation.install =>
          _t(
            'Instalando... aguardando confirmação do UAC',
            'Installing... waiting for UAC confirmation',
          ),
        WindowsServiceOperation.uninstall =>
          _t(
            'Removendo... aguardando confirmação do UAC',
            'Removing... waiting for UAC confirmation',
          ),
        WindowsServiceOperation.start =>
          _t(
            'Iniciando... aguardando confirmação do UAC',
            'Starting... waiting for UAC confirmation',
          ),
        WindowsServiceOperation.stop =>
          _t(
            'Parando... aguardando confirmação do UAC',
            'Stopping... waiting for UAC confirmation',
          ),
        WindowsServiceOperation.restart =>
          _t(
            'Reiniciando... aguardando confirmação do UAC',
            'Restarting... waiting for UAC confirmation',
          ),
        WindowsServiceOperation.check =>
          _t('Verificando...', 'Checking...'),
        WindowsServiceOperation.none =>
          _t('Verificando...', 'Checking...'),
      };
    }
    if (provider.isInstalled) {
      return provider.isRunning
          ? _t('Instalado e em execução', 'Installed and running')
          : _t('Instalado', 'Installed');
    }
    return _t('Não instalado', 'Not installed');
  }

  bool _shouldShowUacInfoBar(WindowsServiceProvider provider) {
    if (!provider.isLoading) {
      return false;
    }
    return provider.operation == WindowsServiceOperation.install ||
        provider.operation == WindowsServiceOperation.uninstall ||
        provider.operation == WindowsServiceOperation.start ||
        provider.operation == WindowsServiceOperation.stop ||
        provider.operation == WindowsServiceOperation.restart;
  }

  String _getUacInfoBarMessage(WindowsServiceProvider provider) {
    return switch (provider.operation) {
      WindowsServiceOperation.install => _t(
        'Confirme o prompt do Windows para instalar o serviço.',
        'Confirm the Windows prompt to install the service.',
      ),
      WindowsServiceOperation.uninstall => _t(
        'Confirme o prompt do Windows para remover o serviço.',
        'Confirm the Windows prompt to remove the service.',
      ),
      WindowsServiceOperation.start => _t(
        'Confirme o prompt do Windows para iniciar o serviço.',
        'Confirm the Windows prompt to start the service.',
      ),
      WindowsServiceOperation.stop => _t(
        'Confirme o prompt do Windows para parar o serviço.',
        'Confirm the Windows prompt to stop the service.',
      ),
      WindowsServiceOperation.restart => _t(
        'Confirme o prompt do Windows para reiniciar o serviço.',
        'Confirm the Windows prompt to restart the service.',
      ),
      _ => _t(
        'Confirme o prompt do Windows para continuar.',
        'Confirm the Windows prompt to continue.',
      ),
    };
  }

  Future<void> _installService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(_t('Instalar serviço', 'Install service')),
        content: Text(
          _t(
            'Deseja instalar o Backup Database como serviço do Windows?\n\nO serviço será configurado para:\n- Iniciar automaticamente com o Windows\n- Executar sem usuário logado\n- Rodar com conta LocalSystem\n\nRequisitos:\n- Configure os backups antes de instalar\n- Certifique-se de ter permissões de administrador',
            'Do you want to install Backup Database as a Windows service?\n\nThe service will be configured to:\n- Start automatically with Windows\n- Run without logged-in user\n- Run under LocalSystem account\n\nRequirements:\n- Configure backups before installing\n- Ensure you have administrator permissions',
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_t('Instalar', 'Install')),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      final success = await provider.installService();

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(
              success ? _t('Sucesso', 'Success') : _t('Erro', 'Error'),
            ),
            content: Text(
              success
                  ? _t(
                      'Serviço instalado com sucesso!\n\nO serviço foi configurado e iniciará automaticamente com o Windows.',
                      'Service installed successfully!\n\nThe service was configured and will start automatically with Windows.',
                    )
                  : provider.error ??
                        _t(
                          'Erro desconhecido ao instalar serviço.',
                          'Unknown error while installing service.',
                        ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_t('OK', 'OK')),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _uninstallService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(_t('Remover serviço', 'Remove service')),
        content: Text(
          _t(
            'Deseja realmente remover o serviço do Windows?\n\nOs agendamentos e configurações não serão perdidos, mas o serviço não executará mais automaticamente.',
            'Do you really want to remove the Windows service?\n\nSchedules and settings will not be lost, but the service will no longer run automatically.',
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_t('Remover', 'Remove')),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      final success = await provider.uninstallService();

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(
              success ? _t('Sucesso', 'Success') : _t('Erro', 'Error'),
            ),
            content: Text(
              success
                  ? _t(
                      'Serviço removido com sucesso!',
                      'Service removed successfully!',
                    )
                  : provider.error ??
                        _t(
                          'Erro desconhecido ao remover serviço.',
                          'Unknown error while removing service.',
                        ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_t('OK', 'OK')),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _startService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    final success = await provider.startService();

    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (context) => ContentDialog(
          title: Text(success ? _t('Sucesso', 'Success') : _t('Erro', 'Error')),
          content: Text(
            success
                ? _t(
                    'Serviço iniciado com sucesso!',
                    'Service started successfully!',
                  )
                : provider.error ??
                      _t('Erro ao iniciar serviço.', 'Error starting service.'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t('OK', 'OK')),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _restartService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(_t('Reiniciar serviço', 'Restart service')),
        content: Text(
          _t(
            'Deseja reiniciar o serviço?\n\nO serviço será parado e iniciado novamente. Os backups em execução serão interrompidos.',
            'Do you want to restart the service?\n\nThe service will be stopped and started again. Running backups will be interrupted.',
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_t('Reiniciar', 'Restart')),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      final success = await provider.restartService();

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(
              success ? _t('Sucesso', 'Success') : _t('Erro', 'Error'),
            ),
            content: Text(
              success
                  ? _t(
                      'Serviço reiniciado com sucesso!',
                      'Service restarted successfully!',
                    )
                  : provider.error ??
                        _t(
                          'Erro ao reiniciar serviço.',
                          'Error restarting service.',
                        ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_t('OK', 'OK')),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _stopService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(_t('Parar serviço', 'Stop service')),
        content: Text(
          _t(
            'Deseja parar o serviço?\n\nOs backups agendados não serão executados até que o serviço seja iniciado novamente.',
            'Do you want to stop the service?\n\nScheduled backups will not run until the service is started again.',
          ),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_t('Parar', 'Stop')),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      final success = await provider.stopService();

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(
              success ? _t('Sucesso', 'Success') : _t('Erro', 'Error'),
            ),
            content: Text(
              success
                  ? _t(
                      'Serviço parado com sucesso!',
                      'Service stopped successfully!',
                    )
                  : provider.error ??
                        _t('Erro ao parar serviço.', 'Error stopping service.'),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_t('OK', 'OK')),
              ),
            ],
          ),
        );
      }
    }
  }
}
