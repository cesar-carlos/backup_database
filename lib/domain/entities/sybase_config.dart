import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'sybase_config.freezed.dart';

@freezed
abstract class SybaseConfig
    with _$SybaseConfig
    implements DatabaseConnectionConfig {
  const SybaseConfig._();

  factory SybaseConfig({
    required String name,
    required String serverName,
    required DatabaseName databaseName,
    required String username,
    required String password,
    String? id,
    String databaseFile = '',
    PortNumber? port,
    bool enabled = true,
    bool isReplicationEnvironment = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SybaseConfig.raw(
      id: id ?? const Uuid().v4(),
      name: name,
      serverName: serverName,
      databaseName: databaseName,
      username: username,
      password: password,
      databaseFile: databaseFile,
      port: port ?? PortNumber(2638),
      enabled: enabled,
      isReplicationEnvironment: isReplicationEnvironment,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  const factory SybaseConfig.raw({
    required String id,
    required String name,
    required String serverName,
    required DatabaseName databaseName,
    required String username,
    required String password,
    required PortNumber port,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default('') String databaseFile,
    @Default(true) bool enabled,
    @Default(false) bool isReplicationEnvironment,
  }) = _SybaseConfig;

  @override
  DatabaseType get databaseType => DatabaseType.sybase;

  @override
  String get host => serverName;

  @override
  DatabaseName get primaryDatabase => databaseName;

  @override
  String? get backupTarget => null;

  @override
  int get portValue => port.value;

  String get databaseNameValue => databaseName.value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SybaseConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
