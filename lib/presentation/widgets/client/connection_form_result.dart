class ConnectionFormResult {
  const ConnectionFormResult({
    required this.name,
    required this.serverId,
    required this.host,
    required this.port,
    required this.password,
  });

  final String name;
  final String serverId;
  final String host;
  final int port;
  final String password;
}
