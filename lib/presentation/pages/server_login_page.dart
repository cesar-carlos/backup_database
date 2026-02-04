import 'package:backup_database/application/providers/connection_log_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/domain/entities/connection_log.dart';
import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/presentation/widgets/client/client.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class ServerLoginPage extends StatelessWidget {
  const ServerLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Conectar ao Servidor'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: () {
                context.read<ServerConnectionProvider>().loadConnections();
              },
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('Adicionar Servidor'),
              onPressed: () => _showConnectionDialog(context, null),
            ),
          ],
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Consumer<ServerConnectionProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading) {
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
                              style: FluentTheme.of(
                                context,
                              ).typography.bodyLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Button(
                              onPressed: () => provider.loadConnections(),
                              child: const Text('Tentar Novamente'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (provider.connections.isEmpty) {
                    return AppCard(
                      child: EmptyState(
                        icon: FluentIcons.server,
                        message: 'Nenhum servidor salvo',
                        actionLabel: 'Adicionar Servidor',
                        onAction: () => _showConnectionDialog(context, null),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: provider.connections.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final connection = provider.connections[index];
                      final isActive =
                          provider.activeHost == connection.host &&
                          provider.activePort == connection.port;
                      return ServerListItem(
                        connection: connection,
                        isActiveConnection: isActive,
                        connectionStatus: provider.connectionStatus,
                        onConnect: () => _onConnectPressed(context, connection),
                        onEdit: () =>
                            _showConnectionDialog(context, connection),
                        onDelete: () => _confirmDelete(context, connection.id),
                        onTestConnection: () =>
                            _testConnection(context, connection),
                        onShowLogs: () =>
                            _showConnectionLogs(context, connection),
                        isConnecting: provider.isConnecting,
                        isTestingConnection: provider.isTestingConnection,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onConnectPressed(
    BuildContext context,
    ServerConnection connection,
  ) async {
    final provider = context.read<ServerConnectionProvider>();
    final isActive =
        provider.activeHost == connection.host &&
        provider.activePort == connection.port;
    if (provider.isConnected && isActive) {
      await provider.disconnect();
    } else {
      await provider.connectTo(connection.id);
    }
  }

  Future<void> _showConnectionDialog(
    BuildContext context,
    ServerConnection? connection,
  ) async {
    final formResult = await ConnectionDialog.show(
      context,
      connection: connection,
    );

    if (formResult == null || !context.mounted) return;

    final provider = context.read<ServerConnectionProvider>();

    if (connection == null) {
      final success = await provider.saveConnection(
        name: formResult.name,
        serverId: formResult.serverId,
        host: formResult.host,
        port: formResult.port,
        password: formResult.password,
      );
      if (context.mounted) {
        if (success) {
          MessageModal.showSuccess(
            context,
            message: 'Conexão salva com sucesso.',
          );
        } else {
          MessageModal.showError(
            context,
            message: provider.error ?? 'Erro ao salvar conexão.',
          );
        }
      }
    } else {
      final success = await provider.updateConnection(
        connection,
        name: formResult.name,
        serverId: formResult.serverId,
        host: formResult.host,
        port: formResult.port,
        password: formResult.password,
      );
      if (context.mounted) {
        if (success) {
          MessageModal.showSuccess(
            context,
            message: 'Conexão atualizada com sucesso.',
          );
        } else {
          MessageModal.showError(
            context,
            message: provider.error ?? 'Erro ao atualizar conexão.',
          );
        }
      }
    }
  }

  Future<void> _showConnectionLogs(
    BuildContext context,
    ServerConnection connection,
  ) async {
    context.read<ConnectionLogProvider>().loadLogs();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: Text('Log de conexão: ${connection.name}'),
          content: SizedBox(
            width: 420,
            height: 320,
            child: Consumer<ConnectionLogProvider>(
              builder: (context, logProvider, _) {
                if (logProvider.isLoading && logProvider.logs.isEmpty) {
                  return const Center(child: ProgressRing());
                }
                final filtered = logProvider.logs
                    .where(
                      (l) =>
                          l.clientHost == connection.name ||
                          l.serverId == connection.serverId,
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'Nenhum registro para esta conexão.',
                      style: FluentTheme.of(context).typography.body,
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) => _ConnectionLogRowCompact(
                    log: filtered[i],
                  ),
                );
              },
            ),
          ),
          actions: [
            Button(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _testConnection(
    BuildContext context,
    ServerConnection connection,
  ) async {
    final provider = context.read<ServerConnectionProvider>();
    final ok = await provider.testConnection(connection);
    if (!context.mounted) return;
    if (ok) {
      MessageModal.showSuccess(
        context,
        message:
            'Conexão bem-sucedida com ${connection.host}:${connection.port}',
      );
    } else {
      MessageModal.showError(
        context,
        message: provider.error ?? 'Falha ao conectar.',
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir esta conexão salva?',
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          Button(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final provider = context.read<ServerConnectionProvider>();
    final success = await provider.deleteConnection(id);

    if (context.mounted) {
      if (success) {
        MessageModal.showSuccess(
          context,
          message: 'Conexão excluída com sucesso.',
        );
      } else {
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao excluir conexão.',
        );
      }
    }
  }
}

class _ConnectionLogRowCompact extends StatelessWidget {
  const _ConnectionLogRowCompact({required this.log});

  final ConnectionLog log;

  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final color = log.success ? AppColors.success : AppColors.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dateFormat.format(log.timestamp),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  if (log.errorMessage != null &&
                      log.errorMessage!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SelectableText(
                      log.errorMessage!,
                      style: FluentTheme.of(context).typography.body?.copyWith(
                        color: AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    log.success ? FluentIcons.check_mark : FluentIcons.cancel,
                    size: 12,
                    color: color,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    log.success ? 'Sucesso' : 'Falha',
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      color: color,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
