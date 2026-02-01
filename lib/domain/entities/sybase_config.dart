import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:uuid/uuid.dart';

class SybaseConfig {
  SybaseConfig({
    required this.name,
    required this.serverName,
    required DatabaseName databaseName,
    required this.username,
    required this.password,
    String? id,
    this.databaseFile = '',
    PortNumber? port,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       databaseName = databaseName,
       port = port ?? PortNumber(2638),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final String serverName;
  final DatabaseName databaseName;
  final String databaseFile;
  final PortNumber port;
  final String username;
  final String password;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get databaseNameValue => databaseName.value;
  int get portValue => port.value;

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
