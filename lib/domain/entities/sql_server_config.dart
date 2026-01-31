import 'package:uuid/uuid.dart';

class SqlServerConfig {
  SqlServerConfig({
    required this.name,
    required this.server,
    required this.database,
    required this.username,
    required this.password,
    String? id,
    this.port = 1433,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
  final String id;
  final String name;
  final String server;
  final String database;
  final String username;
  final String password;
  final int port;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  SqlServerConfig copyWith({
    String? id,
    String? name,
    String? server,
    String? database,
    String? username,
    String? password,
    int? port,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SqlServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      server: server ?? this.server,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      port: port ?? this.port,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SqlServerConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
