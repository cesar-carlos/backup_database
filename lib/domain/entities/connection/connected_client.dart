class ConnectedClient {
  const ConnectedClient({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.host,
    required this.port,
    required this.connectedAt,
    required this.lastHeartbeat,
    required this.isAuthenticated,
    this.monitoredScheduleIds = const [],
  });

  final String id;
  final String clientId;
  final String clientName;
  final String host;
  final int port;
  final DateTime connectedAt;
  final DateTime lastHeartbeat;
  final bool isAuthenticated;
  final List<String> monitoredScheduleIds;
}
