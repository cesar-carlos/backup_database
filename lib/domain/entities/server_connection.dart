class ServerConnection {
  const ServerConnection({
    required this.id,
    required this.name,
    required this.serverId,
    required this.host,
    required this.port,
    required this.password,
    required this.isOnline,
    required this.createdAt,
    required this.updatedAt,
    this.lastConnectedAt,
  });

  final String id;
  final String name;
  final String serverId;
  final String host;
  final int port;
  final String password;
  final bool isOnline;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastConnectedAt;

  ServerConnection copyWith({
    String? id,
    String? name,
    String? serverId,
    String? host,
    int? port,
    String? password,
    bool? isOnline,
    DateTime? lastConnectedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServerConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      serverId: serverId ?? this.serverId,
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      isOnline: isOnline ?? this.isOnline,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerConnection && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
