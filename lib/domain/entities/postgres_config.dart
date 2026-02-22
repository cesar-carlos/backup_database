import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:uuid/uuid.dart';

class PostgresConfig {
  PostgresConfig({
    required this.name,
    required this.host,
    required this.database,
    required this.username,
    required this.password,
    String? id,
    PortNumber? port,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       port = port ?? PortNumber(5432),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final String host;
  final PortNumber port;
  final DatabaseName database;
  final String username;
  final String password;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get databaseValue => database.value;
  int get portValue => port.value;

  PostgresConfig copyWith({
    String? id,
    String? name,
    String? host,
    PortNumber? port,
    DatabaseName? database,
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
