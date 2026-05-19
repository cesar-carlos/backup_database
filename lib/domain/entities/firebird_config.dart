import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'firebird_config.freezed.dart';

@freezed
abstract class FirebirdConfig
    with _$FirebirdConfig
    implements DatabaseConnectionConfig {
  const FirebirdConfig._();

  factory FirebirdConfig({
    required String name,
    required String host,
    required String databaseFile,
    required String username,
    required String password,
    String? id,
    PortNumber? port,
    String? aliasName,
    bool useEmbedded = false,
    String? clientLibraryPath,
    FirebirdServerVersionHint serverVersionHint =
        FirebirdServerVersionHint.auto,
    FirebirdServiceManagerMode serviceManagerMode =
        FirebirdServiceManagerMode.auto,
    String cryptKey = '',
    bool enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final normalizedHost = host.trim().isEmpty ? 'localhost' : host.trim();
    return FirebirdConfig.raw(
      id: id ?? const Uuid().v4(),
      name: name,
      host: normalizedHost,
      databaseFile: databaseFile,
      username: username,
      password: password,
      port: port ?? PortNumber(3050),
      aliasName: aliasName,
      useEmbedded: useEmbedded,
      clientLibraryPath: clientLibraryPath,
      serverVersionHint: serverVersionHint,
      serviceManagerMode: serviceManagerMode,
      cryptKey: cryptKey,
      enabled: enabled,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  const factory FirebirdConfig.raw({
    required String id,
    required String name,
    required String host,
    required String databaseFile,
    required String username,
    required String password,
    required PortNumber port,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? aliasName,
    @Default(false) bool useEmbedded,
    String? clientLibraryPath,
    @Default(FirebirdServerVersionHint.auto)
    FirebirdServerVersionHint serverVersionHint,
    @Default(FirebirdServiceManagerMode.auto)
    FirebirdServiceManagerMode serviceManagerMode,
    @Default('') String cryptKey,
    @Default(true) bool enabled,
  }) = _FirebirdConfig;

  @override
  DatabaseType get databaseType => DatabaseType.firebird;

  @override
  DatabaseName get primaryDatabase => DatabaseName(
    firebirdPrimaryLabel(
      aliasName: aliasName,
      databaseFile: databaseFile,
    ),
  );

  @override
  String? get backupTarget => databaseFile;

  @override
  int get portValue => port.value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebirdConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

String firebirdPrimaryLabel({
  required String? aliasName,
  required String databaseFile,
}) {
  final trimmed = aliasName?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    return trimmed;
  }
  return firebirdStemFromDatabasePath(databaseFile);
}

String firebirdStemFromDatabasePath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return 'firebird_db';
  }
  final base = trimmed.replaceAll('/', r'\');
  final segs = base.split(r'\');
  var file = segs.isNotEmpty ? segs.last : base;
  if (file.toLowerCase().endsWith('.fdb')) {
    file = file.substring(0, file.length - 4);
  }
  file = file.replaceAll(RegExp(r'[*?"<>|\x00\r\n\t/\\]'), '_');
  if (file.isEmpty) {
    file = 'firebird_db';
  }
  if (file.length > 128) {
    file = file.substring(0, 128);
  }
  return file;
}
