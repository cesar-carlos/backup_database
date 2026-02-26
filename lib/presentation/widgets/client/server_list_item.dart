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
    this.onShowLogs,
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
  final VoidCallback? onShowLogs;
  final bool isConnecting;
  final bool isTestingConnection;

  bool get _isConnectedToThis =>
      connectionStatus == ConnectionStatus.connected && isActiveConnection;

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
                        '${connection.host}:${connection.port} - Server ID: ${connection.serverId}',
                        style: FluentTheme.of(context).typography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (connection.lastConnectedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_t(context, 'Última conexão', 'Last connection')}: ${_formatDate(context, connection.lastConnectedAt!)}',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                      ],
                    ],
                  ),
                ),
                _buildStatusChip(context),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onTestConnection != null) ...[
                        Tooltip(
                          message: _t(
                            context,
                            'Testar conexão',
                            'Test connection',
                          ),
                          child: IconButton(
                            icon: const Icon(FluentIcons.link),
                            onPressed: isTestingConnection
                                ? null
                                : onTestConnection,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (onConnect != null) ...[
                        Tooltip(
                          message: _isConnectedToThis
                              ? _t(context, 'Desconectar', 'Disconnect')
                              : _t(context, 'Conectar', 'Connect'),
                          child: IconButton(
                            icon: Icon(
                              _isConnectedToThis
                                  ? FluentIcons.plug_disconnected
                                  : FluentIcons.plug,
                            ),
                            onPressed: isConnecting ? null : onConnect,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (onShowLogs != null) ...[
                        Tooltip(
                          message: _t(
                            context,
                            'Log desta conexão',
                            'Connection log',
                          ),
                          child: IconButton(
                            icon: const Icon(FluentIcons.history),
                            onPressed: onShowLogs,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (onEdit != null) ...[
                        Button(
                          onPressed: onEdit,
                          child: Text(
                            _t(context, 'Esta conexão', 'This connection'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: _t(
                            context,
                            'Editar conexão',
                            'Edit connection',
                          ),
                          child: IconButton(
                            icon: const Icon(FluentIcons.edit),
                            onPressed: onEdit,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (onDelete != null)
                        IconButton(
                          icon: const Icon(FluentIcons.delete),
                          onPressed: onDelete,
                        ),
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
        _t(context, 'Conectando...', 'Connecting...'),
        FluentIcons.sync,
        FluentTheme.of(context).accentColor,
      );
    }
    if (_isConnectedToThis) {
      return (
        _t(context, 'Conectado', 'Connected'),
        FluentIcons.check_mark,
        FluentTheme.of(context).accentColor,
      );
    }
    return (
      _t(context, 'Offline', 'Offline'),
      FluentIcons.circle_stop,
      FluentTheme.of(context).resources.textFillColorSecondary,
    );
  }

  String _formatDate(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    final isPt =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'pt';

    if (diff.inDays > 0) {
      return isPt ? '${diff.inDays}d atras' : '${diff.inDays}d ago';
    }
    if (diff.inHours > 0) {
      return isPt ? '${diff.inHours}h atras' : '${diff.inHours}h ago';
    }
    if (diff.inMinutes > 0) {
      return isPt ? '${diff.inMinutes}min atras' : '${diff.inMinutes}min ago';
    }
    return _t(context, 'Agora', 'Now');
  }
}
