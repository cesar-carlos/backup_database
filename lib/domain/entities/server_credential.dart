class ServerCredential {
  const ServerCredential({
    required this.id,
    required this.serverId,
    required this.passwordHash,
    required this.name,
    required this.isActive,
    required this.createdAt,
    this.lastUsedAt,
    this.description,
  });

  final String id;
  final String serverId;
  final String passwordHash;
  final String name;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final String? description;

  ServerCredential copyWith({
    String? id,
    String? serverId,
    String? passwordHash,
    String? name,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    String? description,
  }) {
    return ServerCredential(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      passwordHash: passwordHash ?? this.passwordHash,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      description: description ?? this.description,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerCredential && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
