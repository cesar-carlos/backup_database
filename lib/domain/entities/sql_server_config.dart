import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'sql_server_config.freezed.dart';

@freezed
abstract class SqlServerConfig
    with _$SqlServerConfig
    implements DatabaseConnectionConfig {
  const SqlServerConfig._();

  factory SqlServerConfig({
    required String name,
    required String server,
    required DatabaseName database,
    required String username,
    required String password,
    String? id,
    PortNumber? port,
    bool enabled = true,
    bool useWindowsAuth = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SqlServerConfig.raw(
      id: id ?? const Uuid().v4(),
      name: name,
      server: server,
      database: database,
      username: username,
      password: password,
      port: port ?? PortNumber(1433),
      enabled: enabled,
      useWindowsAuth: useWindowsAuth,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  const factory SqlServerConfig.raw({
    required String id,
    required String name,
    required String server,
    required DatabaseName database,
    required String username,
    required String password,
    required PortNumber port,
    required DateTime createdAt, required DateTime updatedAt, @Default(true) bool enabled,
    @Default(false) bool useWindowsAuth,
  }) = _SqlServerConfig;

  @override
  DatabaseType get databaseType => DatabaseType.sqlServer;

  @override
  String get host => server;

  @override
  DatabaseName get primaryDatabase => database;

  @override
  String? get backupTarget => null;

  @override
  int get portValue => port.value;

  String get databaseValue => database.value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SqlServerConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
