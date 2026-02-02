import 'package:backup_database/domain/entities/server_connection.dart';
import 'package:backup_database/infrastructure/socket/client/socket_client_service.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ServerListItem extends StatelessWidget {
  const ServerListItem({
    required this.connection,
    required this.isActiveConnection,
    required this.connectionStatus,
    super.key,
    this.onConnect,
    this.onEdit,
    this.onDelete,
    this.onTestConnection,
    this.isConnecting = false,
    this.isTestingConnection = false,
  });

  final ServerConnection connection;
  final bool isActiveConnection;
  final ConnectionStatus connectionStatus;
  final VoidCallback? onConnect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTestConnection;
  final bool isConnecting;
  final bool isTestingConnection;

  bool get _isConnectedToThis =>
      connectionStatus == ConnectionStatus.connected && isActiveConnection;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  FluentIcons.server,
                  color: _isConnectedToThis
                      ? FluentTheme.of(context).accentColor
                      : FluentTheme.of(
                          context,
                        ).resources.textFillColorSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.name,
                        style: FluentTheme.of(context).typography.subtitle
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${connection.host}:${connection.port} · Server ID: ${connection.serverId}',
                        style: FluentTheme.of(context).typography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (connection.lastConnectedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Última conexão: ${_formatDate(connection.lastConnectedAt!)}',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                      ],
                    ],
                  ),
                ),
                _buildStatusChip(context),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onTestConnection != null)
                      Tooltip(
                        message: 'Testar conexão',
                        child: IconButton(
                          icon: const Icon(FluentIcons.link),
                          onPressed: isTestingConnection
                              ? null
                              : onTestConnection,
                        ),
                      ),
                    if (onConnect != null)
                      Tooltip(
                        message: _isConnectedToThis
                            ? 'Desconectar'
                            : 'Conectar',
                        child: IconButton(
                          icon: Icon(
                            _isConnectedToThis
                                ? FluentIcons.plug_disconnected
                                : FluentIcons.plug,
                          ),
                          onPressed: isConnecting ? null : onConnect,
                        ),
                      ),
                    if (onEdit != null) ...[
                      Button(
                        onPressed: onEdit,
                        child: const Text('Esta conexão'),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Editar conexão',
                        child: IconButton(
                          icon: const Icon(FluentIcons.edit),
                          onPressed: onEdit,
                        ),
                      ),
                    ],
                    if (onDelete != null)
                      IconButton(
                        icon: const Icon(FluentIcons.delete),
                        onPressed: onDelete,
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    final (String label, IconData icon, Color color) = _getStatusInfo(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: FluentTheme.of(context).typography.caption?.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (String, IconData, Color) _getStatusInfo(BuildContext context) {
    if (isConnecting) {
      return (
        'Conectando...',
        FluentIcons.sync,
        FluentTheme.of(context).accentColor,
      );
    }
    if (_isConnectedToThis) {
      return (
        'Conectado',
        FluentIcons.check_mark,
        FluentTheme.of(context).accentColor,
      );
    }
    return (
      'Offline',
      FluentIcons.circle_stop,
      FluentTheme.of(context).resources.textFillColorSecondary,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d atrás';
    if (diff.inHours > 0) return '${diff.inHours}h atrás';
    if (diff.inMinutes > 0) return '${diff.inMinutes}min atrás';
    return 'Agora';
  }
}
