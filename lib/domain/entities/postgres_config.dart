import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:uuid/uuid.dart';

class PostgresConfig extends DatabaseConnectionConfig {
  PostgresConfig({
    required super.name,
    required String host,
    required this.database,
    required super.username,
    required super.password,
    String? id,
    PortNumber? port,
    super.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : _host = host,
       super(
         id: id ?? const Uuid().v4(),
         port: port ?? PortNumber(5432),
         createdAt: createdAt ?? DateTime.now(),
         updatedAt: updatedAt ?? DateTime.now(),
       );

  final String _host;

  @override
  String get host => _host;
  final DatabaseName database;

  String get databaseValue => database.value;

  @override
  DatabaseType get databaseType => DatabaseType.postgresql;

  @override
  DatabaseName get primaryDatabase => database;

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
