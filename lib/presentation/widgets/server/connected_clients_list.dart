import 'dart:async';

import 'package:backup_database/application/providers/connected_client_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ConnectedClientsList extends StatefulWidget {
  const ConnectedClientsList({super.key});

  @override
  State<ConnectedClientsList> createState() => _ConnectedClientsListState();
}

class _ConnectedClientsListState extends State<ConnectedClientsList> {
  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ConnectedClientProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectedClientProvider>(
      builder: (context, provider, _) {
        if (!provider.isServerRunning) {
          return _buildServerNotRunning(context);
        }
        if (provider.isLoading && provider.clients.isEmpty) {
          return const Center(child: ProgressRing());
        }
        if (provider.error != null) {
          return AppCard(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    FluentIcons.error,
                    size: 64,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    provider.error!,
                    style: FluentTheme.of(context).typography.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Button(
                    onPressed: () => provider.refresh(),
                    child: Text(_t('Tentar novamente', 'Try again')),
                  ),
                ],
              ),
            ),
          );
        }
        if (provider.clients.isEmpty) {
          return AppCard(
            child: EmptyState(
              icon: FluentIcons.people,
              message: _t('Nenhum cliente conectado', 'No connected clients'),
              actionLabel: _t('Atualizar', 'Refresh'),
              onAction: () => provider.refresh(),
            ),
          );
        }
        return _ConnectedClientsContent(provider: provider);
      },
    );
  }

  Widget _buildServerNotRunning(BuildContext context) {
    final provider = context.read<ConnectedClientProvider>();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.server,
              size: 64,
              color: FluentTheme.of(context).resources.textFillColorSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              _t('Servidor nao esta em execucao', 'Server is not running'),
              style: FluentTheme.of(context).typography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Inicie o servidor para aceitar conexoes de clientes.',
                'Start the server to accept client connections.',
              ),
              style: FluentTheme.of(context).typography.body,
              textAlign: TextAlign.center,
            ),
            if (provider.error != null) ...[
              const SizedBox(height: 16),
              Text(
                provider.error!,
                style: FluentTheme.of(
                  context,
                ).typography.body?.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: provider.startServer,
              child: Text(_t('Iniciar servidor', 'Start server')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedClientsContent extends StatefulWidget {
  const _ConnectedClientsContent({required this.provider});

  final ConnectedClientProvider provider;

  @override
  State<_ConnectedClientsContent> createState() =>
      _ConnectedClientsContentState();
}

class _ConnectedClientsContentState extends State<_ConnectedClientsContent> {
  static const Duration _pollInterval = Duration(seconds: 5);
  Timer? _pollTimer;

  String _t(String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (mounted) widget.provider.refresh();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: () => widget.provider.refresh(),
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.stop),
              label: Text(_t('Parar servidor', 'Stop server')),
              onPressed: () => widget.provider.stopServer(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: widget.provider.clients.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final client = widget.provider.clients[index];
              return _ConnectedClientRow(
                client: client,
                onDisconnect: () =>
                    widget.provider.disconnectClient(client.clientId),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConnectedClientRow extends StatelessWidget {
  const _ConnectedClientRow({
    required this.client,
    required this.onDisconnect,
  });

  final ConnectedClient client;
  final VoidCallback onDisconnect;

  String _t(BuildContext context, String pt, String en) {
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';
    return isPt ? pt : en;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              FluentIcons.contact,
              color: FluentTheme.of(context).accentColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client.clientName.isNotEmpty
                        ? client.clientName
                        : client.clientId,
                    style: FluentTheme.of(context).typography.subtitle
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${client.host}:${client.port}',
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_t(context, 'Conectado', 'Connected')}: ${_formatDateTime(context, client.connectedAt)} · '
                    '${_t(context, 'Ultimo heartbeat', 'Last heartbeat')}: ${_formatDateTime(context, client.lastHeartbeat)}',
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ],
              ),
            ),
            _buildAuthChip(context),
            const SizedBox(width: 8),
            Tooltip(
              message: _t(context, 'Desconectar', 'Disconnect'),
              child: IconButton(
                icon: const Icon(FluentIcons.plug_disconnected),
                onPressed: onDisconnect,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthChip(BuildContext context) {
    final color = client.isAuthenticated
        ? AppColors.success
        : FluentTheme.of(context).resources.textFillColorSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        client.isAuthenticated
            ? _t(context, 'Autenticado', 'Authenticated')
            : _t(context, 'Nao autenticado', 'Not authenticated'),
        style: FluentTheme.of(context).typography.caption?.copyWith(
          color: color,
        ),
      ),
    );
  }

  String _formatDateTime(BuildContext context, DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 0) {
      return _t(context, '${diff.inDays}d atras', '${diff.inDays}d ago');
    }
    if (diff.inHours > 0) {
      return _t(context, '${diff.inHours}h atras', '${diff.inHours}h ago');
    }
    if (diff.inMinutes > 0) {
      return _t(
        context,
        '${diff.inMinutes}min atras',
        '${diff.inMinutes}m ago',
      );
    }
    return _t(context, 'Agora', 'Now');
  }
}
