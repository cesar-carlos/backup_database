import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:uuid/uuid.dart';

class SybaseConfig extends DatabaseConnectionConfig {
  SybaseConfig({
    required super.name,
    required this.serverName,
    required this.databaseName,
    required super.username,
    required super.password,
    String? id,
    this.databaseFile = '',
    PortNumber? port,
    super.enabled = true,
    this.isReplicationEnvironment = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : super(
         id: id ?? const Uuid().v4(),
         port: port ?? PortNumber(2638),
         createdAt: createdAt ?? DateTime.now(),
         updatedAt: updatedAt ?? DateTime.now(),
       );

  final String serverName;
  final DatabaseName databaseName;
  final String databaseFile;
  final bool isReplicationEnvironment;

  String get databaseNameValue => databaseName.value;

  @override
  DatabaseType get databaseType => DatabaseType.sybase;

  @override
  String get host => serverName;

  @override
  DatabaseName get primaryDatabase => databaseName;

  SybaseConfig copyWith({
    String? id,
    String? name,
    String? serverName,
    DatabaseName? databaseName,
    String? databaseFile,
    PortNumber? port,
    String? username,
    String? password,
    bool? enabled,
    bool? isReplicationEnvironment,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SybaseConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      serverName: serverName ?? this.serverName,
      databaseName: databaseName ?? this.databaseName,
      databaseFile: databaseFile ?? this.databaseFile,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      enabled: enabled ?? this.enabled,
      isReplicationEnvironment:
          isReplicationEnvironment ?? this.isReplicationEnvironment,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SybaseConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
