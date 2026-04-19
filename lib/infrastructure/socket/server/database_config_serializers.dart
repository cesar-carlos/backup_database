import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';
import 'package:backup_database/domain/value_objects/port_number.dart';

/// Serializadores opacos Map<->Entity para o protocolo de CRUD remoto
/// de database config.
///
/// O protocolo trafega `Map<String, dynamic>` neutro (ver
/// `database_config_messages.dart` — campo `config` ad-hoc) para nao
/// acoplar o cliente as entities tipadas. Aqui ficam os converters
/// usados pelo `RealDatabaseConfigStore` no servidor para mapear
/// payload -> entity antes de chamar o repository, e entity -> payload
/// depois de buscar.
///
/// Decisao consciente: NAO incluir `password` nos snapshots de saida
/// quando a config ja existe persistida (evita roundtrip do segredo).
/// Cliente que precisa renovar senha envia novo `config` via update.
class DatabaseConfigSerializers {
  DatabaseConfigSerializers._();

  // ---------------------------------------------------------------
  // Sybase
  // ---------------------------------------------------------------

  static SybaseConfig sybaseFromMap(Map<String, dynamic> map) {
    return SybaseConfig(
      id: map['id'] is String ? map['id'] as String : null,
      name: _requireString(map, 'name'),
      serverName: _requireString(map, 'serverName'),
      databaseName: DatabaseName(_requireString(map, 'databaseName')),
      databaseFile: map['databaseFile'] is String
          ? map['databaseFile'] as String
          : '',
      port: PortNumber(_intOr(map, 'port', 2638)),
      username: _requireString(map, 'username'),
      password: map['password'] is String ? map['password'] as String : '',
      enabled: map['enabled'] is! bool || (map['enabled'] as bool),
      isReplicationEnvironment: map['isReplicationEnvironment'] is bool &&
          (map['isReplicationEnvironment'] as bool),
      createdAt: _dateOrNow(map, 'createdAt'),
      updatedAt: _dateOrNow(map, 'updatedAt'),
    );
  }

  /// `includePassword=false` (default) NAO inclui o segredo na saida —
  /// usado em respostas de listagem/get. `true` apenas em casos onde
  /// o cliente precisa receber a config completa (raro; quase sempre
  /// ele ja tem a senha que ele mesmo enviou).
  static Map<String, dynamic> sybaseToMap(
    SybaseConfig cfg, {
    bool includePassword = false,
  }) {
    return <String, dynamic>{
      'id': cfg.id,
      'name': cfg.name,
      'serverName': cfg.serverName,
      'databaseName': cfg.databaseNameValue,
      'databaseFile': cfg.databaseFile,
      'port': cfg.portValue,
      'username': cfg.username,
      if (includePassword) 'password': cfg.password,
      'enabled': cfg.enabled,
      'isReplicationEnvironment': cfg.isReplicationEnvironment,
      'createdAt': cfg.createdAt.toUtc().toIso8601String(),
      'updatedAt': cfg.updatedAt.toUtc().toIso8601String(),
    };
  }

  // ---------------------------------------------------------------
  // SQL Server
  // ---------------------------------------------------------------

  static SqlServerConfig sqlServerFromMap(Map<String, dynamic> map) {
    return SqlServerConfig(
      id: map['id'] is String ? map['id'] as String : null,
      name: _requireString(map, 'name'),
      server: _requireString(map, 'server'),
      database: DatabaseName(_requireString(map, 'database')),
      username: map['username'] is String ? map['username'] as String : '',
      password: map['password'] is String ? map['password'] as String : '',
      port: PortNumber(_intOr(map, 'port', 1433)),
      enabled: map['enabled'] is! bool || (map['enabled'] as bool),
      useWindowsAuth:
          map['useWindowsAuth'] is bool && (map['useWindowsAuth'] as bool),
      createdAt: _dateOrNow(map, 'createdAt'),
      updatedAt: _dateOrNow(map, 'updatedAt'),
    );
  }

  static Map<String, dynamic> sqlServerToMap(
    SqlServerConfig cfg, {
    bool includePassword = false,
  }) {
    return <String, dynamic>{
      'id': cfg.id,
      'name': cfg.name,
      'server': cfg.server,
      'database': cfg.databaseValue,
      'username': cfg.username,
      if (includePassword) 'password': cfg.password,
      'port': cfg.portValue,
      'enabled': cfg.enabled,
      'useWindowsAuth': cfg.useWindowsAuth,
      'createdAt': cfg.createdAt.toUtc().toIso8601String(),
      'updatedAt': cfg.updatedAt.toUtc().toIso8601String(),
    };
  }

  // ---------------------------------------------------------------
  // Postgres
  // ---------------------------------------------------------------

  static PostgresConfig postgresFromMap(Map<String, dynamic> map) {
    return PostgresConfig(
      id: map['id'] is String ? map['id'] as String : null,
      name: _requireString(map, 'name'),
      host: _requireString(map, 'host'),
      database: DatabaseName(_requireString(map, 'database')),
      username: _requireString(map, 'username'),
      password: map['password'] is String ? map['password'] as String : '',
      port: PortNumber(_intOr(map, 'port', 5432)),
      enabled: map['enabled'] is! bool || (map['enabled'] as bool),
      createdAt: _dateOrNow(map, 'createdAt'),
      updatedAt: _dateOrNow(map, 'updatedAt'),
    );
  }

  static Map<String, dynamic> postgresToMap(
    PostgresConfig cfg, {
    bool includePassword = false,
  }) {
    return <String, dynamic>{
      'id': cfg.id,
      'name': cfg.name,
      'host': cfg.host,
      'database': cfg.databaseValue,
      'username': cfg.username,
      if (includePassword) 'password': cfg.password,
      'port': cfg.portValue,
      'enabled': cfg.enabled,
      'createdAt': cfg.createdAt.toUtc().toIso8601String(),
      'updatedAt': cfg.updatedAt.toUtc().toIso8601String(),
    };
  }

  // ---------------------------------------------------------------
  // Helpers privados
  // ---------------------------------------------------------------

  static String _requireString(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is! String || v.isEmpty) {
      throw ArgumentError(
        'database config payload: campo `$key` ausente ou nao-string',
      );
    }
    return v;
  }

  static int _intOr(Map<String, dynamic> map, String key, int fallback) {
    final v = map[key];
    if (v is int) return v;
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static DateTime _dateOrNow(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }
}
