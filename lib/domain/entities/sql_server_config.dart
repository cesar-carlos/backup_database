import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:uuid/uuid.dart';

class SqlServerConfig {
  SqlServerConfig({
    required this.name,
    required this.server,
    required this.database,
    required this.username,
    required this.password,
    String? id,
    PortNumber? port,
    this.enabled = true,
    this.useWindowsAuth = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       port = port ?? PortNumber(1433),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final String server;
  final DatabaseName database;
  final String username;
  final String password;
  final PortNumber port;
  final bool enabled;
  final bool useWindowsAuth;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get databaseValue => database.value;
  int get portValue => port.value;

  SqlServerConfig copyWith({
    String? id,
    String? name,
    String? server,
    DatabaseName? database,
    String? username,
    String? password,
    PortNumber? port,
    bool? enabled,
    bool? useWindowsAuth,
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
      useWindowsAuth: useWindowsAuth ?? this.useWindowsAuth,
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
