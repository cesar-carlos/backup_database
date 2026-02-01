class ConnectionLog {
  const ConnectionLog({
    required this.id,
    required this.clientHost,
    required this.success,
    required this.timestamp,
    this.serverId,
    this.errorMessage,
    this.clientId,
  });

  final String id;
  final String clientHost;
  final String? serverId;
  final bool success;
  final String? errorMessage;
  final DateTime timestamp;
  final String? clientId;
}
