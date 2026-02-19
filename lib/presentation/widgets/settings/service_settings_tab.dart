import 'package:backup_database/application/providers/windows_service_provider.dart';
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('Servico do Windows', 'Windows Service'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Instale o aplicativo como servico do Windows para executar backups automaticamente, mesmo sem usuario logado.',
                  'Install the app as a Windows service to run backups automatically, even with no logged-in user.',
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: FluentTheme.of(context).typography.body?.color,
                ),
              ),
              const SizedBox(height: 32),
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
              _t('Status do servico', 'Service status'),
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
        child: Row(
          children: [
            Icon(FluentIcons.error_badge, color: Colors.red, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(provider.error!, style: TextStyle(color: Colors.red)),
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
              _t('Acoes', 'Actions'),
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
                        Text(_t('Instalar servico', 'Install service')),
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
                        Text(_t('Remover servico', 'Remove service')),
                      ],
                    ),
                  ),
                  if (provider.isRunning)
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
                    )
                  else
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
              _t('Informacoes', 'Information'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildInfoItem(
              context,
              _t('Funciona sem usuario logado', 'Works without logged-in user'),
              _t(
                'O servico executara backups mesmo quando nenhum usuario estiver conectado.',
                'The service will run backups even when no user is logged in.',
              ),
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              context,
              _t('Inicializacao automatica', 'Automatic startup'),
              _t(
                'O servico iniciara automaticamente com o Windows.',
                'The service will start automatically with Windows.',
              ),
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              context,
              _t('Logs', 'Logs'),
              r'Os logs sao salvos em: C:\ProgramData\BackupDatabase\logs\',
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
    if (provider.isLoading) return _t('Verificando...', 'Checking...');
    if (provider.isInstalled) {
      return provider.isRunning
          ? _t('Instalado e em execucao', 'Installed and running')
          : _t('Instalado', 'Installed');
    }
    return _t('Nao instalado', 'Not installed');
  }

  Future<void> _installService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(_t('Instalar servico', 'Install service')),
        content: Text(
          _t(
            'Deseja instalar o Backup Database como servico do Windows?\n\nO servico sera configurado para:\n- Iniciar automaticamente com o Windows\n- Executar sem usuario logado\n- Rodar com conta LocalSystem\n\nRequisitos:\n- Configure os backups antes de instalar\n- Certifique-se de ter permissoes de administrador',
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
                      'Servico instalado com sucesso!\n\nO servico foi configurado e iniciara automaticamente com o Windows.',
                      'Service installed successfully!\n\nThe service was configured and will start automatically with Windows.',
                    )
                  : provider.error ??
                        _t(
                          'Erro desconhecido ao instalar servico.',
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
        title: Text(_t('Remover servico', 'Remove service')),
        content: Text(
          _t(
            'Deseja realmente remover o servico do Windows?\n\nOs agendamentos e configuracoes nao serao perdidos, mas o servico nao executara mais automaticamente.',
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
                      'Servico removido com sucesso!',
                      'Service removed successfully!',
                    )
                  : provider.error ??
                        _t(
                          'Erro desconhecido ao remover servico.',
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
                    'Servico iniciado com sucesso!',
                    'Service started successfully!',
                  )
                : provider.error ??
                      _t('Erro ao iniciar servico.', 'Error starting service.'),
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

  Future<void> _stopService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(_t('Parar servico', 'Stop service')),
        content: Text(
          _t(
            'Deseja parar o servico?\n\nOs backups agendados nao serao executados ate que o servico seja iniciado novamente.',
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
                      'Servico parado com sucesso!',
                      'Service stopped successfully!',
                    )
                  : provider.error ??
                        _t('Erro ao parar servico.', 'Error stopping service.'),
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
