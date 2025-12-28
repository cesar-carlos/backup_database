import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../../application/providers/windows_service_provider.dart';

class ServiceSettingsTab extends StatefulWidget {
  const ServiceSettingsTab({super.key});

  @override
  State<ServiceSettingsTab> createState() => _ServiceSettingsTabState();
}

class _ServiceSettingsTabState extends State<ServiceSettingsTab> {
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
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Serviço do Windows',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Instale o aplicativo como serviço do Windows para executar backups automaticamente, mesmo sem usuário logado.',
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status do Serviço',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: 'Estado',
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
                'Nome: ${provider.status!.serviceName}',
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
        padding: const EdgeInsets.all(16.0),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ações',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.download, size: 16),
                        SizedBox(width: 8),
                        Text('Instalar Serviço'),
                      ],
                    ),
                  ),
                if (provider.isInstalled) ...[
                  FilledButton(
                    onPressed: provider.isLoading
                        ? null
                        : () => _uninstallService(context, provider),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(FluentIcons.delete, size: 16),
                        SizedBox(width: 8),
                        Text('Remover Serviço'),
                      ],
                    ),
                  ),
                  if (provider.isRunning)
                    Button(
                      onPressed: provider.isLoading
                          ? null
                          : () => _stopService(context, provider),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.stop, size: 16),
                          SizedBox(width: 8),
                          Text('Parar'),
                        ],
                      ),
                    )
                  else
                    Button(
                      onPressed: provider.isLoading
                          ? null
                          : () => _startService(context, provider),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.play, size: 16),
                          SizedBox(width: 8),
                          Text('Iniciar'),
                        ],
                      ),
                    ),
                ],
                Button(
                  onPressed: provider.isLoading
                      ? null
                      : () => provider.checkStatus(),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.refresh, size: 16),
                      SizedBox(width: 8),
                      Text('Atualizar Status'),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informações',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildInfoItem(
              context,
              'Funciona sem usuário logado',
              'O serviço executará backups mesmo quando nenhum usuário estiver conectado.',
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              context,
              'Inicialização automática',
              'O serviço iniciará automaticamente com o Windows.',
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              context,
              'Logs',
              'Os logs são salvos em: C:\\ProgramData\\BackupDatabase\\logs\\',
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
    if (provider.isLoading) return 'Verificando...';
    if (provider.isInstalled) {
      return provider.isRunning ? 'Instalado e em execução' : 'Instalado';
    }
    return 'Não instalado';
  }

  Future<void> _installService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Instalar Serviço'),
        content: const Text(
          'Deseja instalar o Backup Database como serviço do Windows?\n\n'
          'O serviço será configurado para:\n'
          '• Iniciar automaticamente com o Windows\n'
          '• Executar sem usuário logado\n'
          '• Rodar com conta LocalSystem\n\n'
          'Requisitos:\n'
          '• Configure os backups antes de instalar\n'
          '• Certifique-se de ter permissões de administrador',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Instalar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await provider.installService();

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(success ? 'Sucesso' : 'Erro'),
            content: Text(
              success
                  ? 'Serviço instalado com sucesso!\n\nO serviço foi configurado e iniciará automaticamente com o Windows.'
                  : provider.error ?? 'Erro desconhecido ao instalar serviço.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
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
        title: const Text('Remover Serviço'),
        content: const Text(
          'Deseja realmente remover o serviço do Windows?\n\n'
          'Os agendamentos e configurações não serão perdidos, '
          'mas o serviço não executará mais automaticamente.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await provider.uninstallService();

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(success ? 'Sucesso' : 'Erro'),
            content: Text(
              success
                  ? 'Serviço removido com sucesso!'
                  : provider.error ?? 'Erro desconhecido ao remover serviço.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
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
          title: Text(success ? 'Sucesso' : 'Erro'),
          content: Text(
            success
                ? 'Serviço iniciado com sucesso!'
                : provider.error ?? 'Erro ao iniciar serviço.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
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
        title: const Text('Parar Serviço'),
        content: const Text(
          'Deseja parar o serviço?\n\n'
          'Os backups agendados não serão executados até que o serviço seja iniciado novamente.',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Parar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await provider.stopService();

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => ContentDialog(
            title: Text(success ? 'Sucesso' : 'Erro'),
            content: Text(
              success
                  ? 'Serviço parado com sucesso!'
                  : provider.error ?? 'Erro ao parar serviço.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}
