import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:uuid/uuid.dart';

class FirebirdConfig extends DatabaseConnectionConfig {
  FirebirdConfig({
    required super.name,
    required String host,
    required this.databaseFile,
    required super.username,
    required super.password,
    String? id,
    PortNumber? port,
    this.aliasName,
    this.useEmbedded = false,
    this.clientLibraryPath,
    this.serverVersionHint = FirebirdServerVersionHint.auto,
    this.serviceManagerMode = FirebirdServiceManagerMode.auto,
    this.cryptKey = '',
    super.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : _host = host.trim().isEmpty ? 'localhost' : host.trim(),
       super(
         id: id ?? const Uuid().v4(),
         port: port ?? PortNumber(3050),
         createdAt: createdAt ?? DateTime.now(),
         updatedAt: updatedAt ?? DateTime.now(),
       );

  final String _host;

  final String databaseFile;
  final String? aliasName;
  final bool useEmbedded;
  final String? clientLibraryPath;
  final FirebirdServerVersionHint serverVersionHint;
  final FirebirdServiceManagerMode serviceManagerMode;
  final String cryptKey;

  @override
  String get host => _host;

  @override
  DatabaseType get databaseType => DatabaseType.firebird;

  @override
  DatabaseName get primaryDatabase {
    final label = _primaryLabelFromAliasOrPath();
    return DatabaseName(label);
  }

  @override
  String? get backupTarget => databaseFile;

  String _primaryLabelFromAliasOrPath() {
    final trimmed = aliasName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return _stemFromDatabasePath(databaseFile);
  }

  static String _stemFromDatabasePath(String path) {
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

  FirebirdConfig copyWith({
    String? id,
    String? name,
    String? host,
    PortNumber? port,
    String? databaseFile,
    String? aliasName,
    bool? useEmbedded,
    String? clientLibraryPath,
    FirebirdServerVersionHint? serverVersionHint,
    FirebirdServiceManagerMode? serviceManagerMode,
    String? username,
    String? password,
    String? cryptKey,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FirebirdConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      databaseFile: databaseFile ?? this.databaseFile,
      username: username ?? this.username,
      password: password ?? this.password,
      port: port ?? this.port,
      aliasName: aliasName ?? this.aliasName,
      useEmbedded: useEmbedded ?? this.useEmbedded,
      clientLibraryPath: clientLibraryPath ?? this.clientLibraryPath,
      serverVersionHint: serverVersionHint ?? this.serverVersionHint,
      serviceManagerMode: serviceManagerMode ?? this.serviceManagerMode,
      cryptKey: cryptKey ?? this.cryptKey,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirebirdConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
