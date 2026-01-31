import 'package:uuid/uuid.dart';

class PostgresConfig {
  PostgresConfig({
    required this.name,
    required this.host,
    required this.database,
    required this.username,
    required this.password,
    String? id,
    this.port = 5432,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
  final String id;
  final String name;
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  PostgresConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostgresConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PostgresConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
