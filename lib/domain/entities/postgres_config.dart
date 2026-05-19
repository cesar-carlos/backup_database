import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'postgres_config.freezed.dart';

@freezed
abstract class PostgresConfig
    with _$PostgresConfig
    implements DatabaseConnectionConfig {
  const PostgresConfig._();

  factory PostgresConfig({
    required String name,
    required String host,
    required DatabaseName database,
    required String username,
    required String password,
    String? id,
    PortNumber? port,
    bool enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PostgresConfig.raw(
      id: id ?? const Uuid().v4(),
      name: name,
      host: host,
      database: database,
      username: username,
      password: password,
      port: port ?? PortNumber(5432),
      enabled: enabled,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  const factory PostgresConfig.raw({
    required String id,
    required String name,
    required String host,
    required DatabaseName database,
    required String username,
    required String password,
    required PortNumber port,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(true) bool enabled,
  }) = _PostgresConfig;

  @override
  DatabaseType get databaseType => DatabaseType.postgresql;

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
      other is PostgresConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
