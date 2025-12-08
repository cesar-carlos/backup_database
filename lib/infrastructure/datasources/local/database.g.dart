// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SqlServerConfigsTableTable extends SqlServerConfigsTable
    with TableInfo<$SqlServerConfigsTableTable, SqlServerConfigsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SqlServerConfigsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverMeta = const VerificationMeta('server');
  @override
  late final GeneratedColumn<String> server = GeneratedColumn<String>(
    'server',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _databaseMeta = const VerificationMeta(
    'database',
  );
  @override
  late final GeneratedColumn<String> database = GeneratedColumn<String>(
    'database',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passwordMeta = const VerificationMeta(
    'password',
  );
  @override
  late final GeneratedColumn<String> password = GeneratedColumn<String>(
    'password',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1433),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    server,
    database,
    username,
    password,
    port,
    enabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sql_server_configs_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<SqlServerConfigsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('server')) {
      context.handle(
        _serverMeta,
        server.isAcceptableOrUnknown(data['server']!, _serverMeta),
      );
    } else if (isInserting) {
      context.missing(_serverMeta);
    }
    if (data.containsKey('database')) {
      context.handle(
        _databaseMeta,
        database.isAcceptableOrUnknown(data['database']!, _databaseMeta),
      );
    } else if (isInserting) {
      context.missing(_databaseMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('password')) {
      context.handle(
        _passwordMeta,
        password.isAcceptableOrUnknown(data['password']!, _passwordMeta),
      );
    } else if (isInserting) {
      context.missing(_passwordMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SqlServerConfigsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SqlServerConfigsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      server: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server'],
      )!,
      database: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}database'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      password: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SqlServerConfigsTableTable createAlias(String alias) {
    return $SqlServerConfigsTableTable(attachedDatabase, alias);
  }
}

class SqlServerConfigsTableData extends DataClass
    implements Insertable<SqlServerConfigsTableData> {
  final String id;
  final String name;
  final String server;
  final String database;
  final String username;
  final String password;
  final int port;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SqlServerConfigsTableData({
    required this.id,
    required this.name,
    required this.server,
    required this.database,
    required this.username,
    required this.password,
    required this.port,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['server'] = Variable<String>(server);
    map['database'] = Variable<String>(database);
    map['username'] = Variable<String>(username);
    map['password'] = Variable<String>(password);
    map['port'] = Variable<int>(port);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SqlServerConfigsTableCompanion toCompanion(bool nullToAbsent) {
    return SqlServerConfigsTableCompanion(
      id: Value(id),
      name: Value(name),
      server: Value(server),
      database: Value(database),
      username: Value(username),
      password: Value(password),
      port: Value(port),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SqlServerConfigsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SqlServerConfigsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      server: serializer.fromJson<String>(json['server']),
      database: serializer.fromJson<String>(json['database']),
      username: serializer.fromJson<String>(json['username']),
      password: serializer.fromJson<String>(json['password']),
      port: serializer.fromJson<int>(json['port']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'server': serializer.toJson<String>(server),
      'database': serializer.toJson<String>(database),
      'username': serializer.toJson<String>(username),
      'password': serializer.toJson<String>(password),
      'port': serializer.toJson<int>(port),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SqlServerConfigsTableData copyWith({
    String? id,
    String? name,
    String? server,
    String? database,
    String? username,
    String? password,
    int? port,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SqlServerConfigsTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    server: server ?? this.server,
    database: database ?? this.database,
    username: username ?? this.username,
    password: password ?? this.password,
    port: port ?? this.port,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SqlServerConfigsTableData copyWithCompanion(
    SqlServerConfigsTableCompanion data,
  ) {
    return SqlServerConfigsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      server: data.server.present ? data.server.value : this.server,
      database: data.database.present ? data.database.value : this.database,
      username: data.username.present ? data.username.value : this.username,
      password: data.password.present ? data.password.value : this.password,
      port: data.port.present ? data.port.value : this.port,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SqlServerConfigsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('server: $server, ')
          ..write('database: $database, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('port: $port, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    server,
    database,
    username,
    password,
    port,
    enabled,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SqlServerConfigsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.server == this.server &&
          other.database == this.database &&
          other.username == this.username &&
          other.password == this.password &&
          other.port == this.port &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SqlServerConfigsTableCompanion
    extends UpdateCompanion<SqlServerConfigsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> server;
  final Value<String> database;
  final Value<String> username;
  final Value<String> password;
  final Value<int> port;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SqlServerConfigsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.server = const Value.absent(),
    this.database = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.port = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SqlServerConfigsTableCompanion.insert({
    required String id,
    required String name,
    required String server,
    required String database,
    required String username,
    required String password,
    this.port = const Value.absent(),
    this.enabled = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       server = Value(server),
       database = Value(database),
       username = Value(username),
       password = Value(password),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SqlServerConfigsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? server,
    Expression<String>? database,
    Expression<String>? username,
    Expression<String>? password,
    Expression<int>? port,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (server != null) 'server': server,
      if (database != null) 'database': database,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (port != null) 'port': port,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SqlServerConfigsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? server,
    Value<String>? database,
    Value<String>? username,
    Value<String>? password,
    Value<int>? port,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SqlServerConfigsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      server: server ?? this.server,
      database: database ?? this.database,
      username: username ?? this.username,
      password: password ?? this.password,
      port: port ?? this.port,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (server.present) {
      map['server'] = Variable<String>(server.value);
    }
    if (database.present) {
      map['database'] = Variable<String>(database.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (password.present) {
      map['password'] = Variable<String>(password.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SqlServerConfigsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('server: $server, ')
          ..write('database: $database, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('port: $port, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SybaseConfigsTableTable extends SybaseConfigsTable
    with TableInfo<$SybaseConfigsTableTable, SybaseConfigsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SybaseConfigsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverNameMeta = const VerificationMeta(
    'serverName',
  );
  @override
  late final GeneratedColumn<String> serverName = GeneratedColumn<String>(
    'server_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _databaseNameMeta = const VerificationMeta(
    'databaseName',
  );
  @override
  late final GeneratedColumn<String> databaseName = GeneratedColumn<String>(
    'database_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _databaseFileMeta = const VerificationMeta(
    'databaseFile',
  );
  @override
  late final GeneratedColumn<String> databaseFile = GeneratedColumn<String>(
    'database_file',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2638),
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passwordMeta = const VerificationMeta(
    'password',
  );
  @override
  late final GeneratedColumn<String> password = GeneratedColumn<String>(
    'password',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    serverName,
    databaseName,
    databaseFile,
    port,
    username,
    password,
    enabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sybase_configs_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<SybaseConfigsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('server_name')) {
      context.handle(
        _serverNameMeta,
        serverName.isAcceptableOrUnknown(data['server_name']!, _serverNameMeta),
      );
    } else if (isInserting) {
      context.missing(_serverNameMeta);
    }
    if (data.containsKey('database_name')) {
      context.handle(
        _databaseNameMeta,
        databaseName.isAcceptableOrUnknown(
          data['database_name']!,
          _databaseNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_databaseNameMeta);
    }
    if (data.containsKey('database_file')) {
      context.handle(
        _databaseFileMeta,
        databaseFile.isAcceptableOrUnknown(
          data['database_file']!,
          _databaseFileMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_databaseFileMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('password')) {
      context.handle(
        _passwordMeta,
        password.isAcceptableOrUnknown(data['password']!, _passwordMeta),
      );
    } else if (isInserting) {
      context.missing(_passwordMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SybaseConfigsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SybaseConfigsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      serverName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_name'],
      )!,
      databaseName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}database_name'],
      )!,
      databaseFile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}database_file'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      password: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SybaseConfigsTableTable createAlias(String alias) {
    return $SybaseConfigsTableTable(attachedDatabase, alias);
  }
}

class SybaseConfigsTableData extends DataClass
    implements Insertable<SybaseConfigsTableData> {
  final String id;
  final String name;
  final String serverName;
  final String databaseName;
  final String databaseFile;
  final int port;
  final String username;
  final String password;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SybaseConfigsTableData({
    required this.id,
    required this.name,
    required this.serverName,
    required this.databaseName,
    required this.databaseFile,
    required this.port,
    required this.username,
    required this.password,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['server_name'] = Variable<String>(serverName);
    map['database_name'] = Variable<String>(databaseName);
    map['database_file'] = Variable<String>(databaseFile);
    map['port'] = Variable<int>(port);
    map['username'] = Variable<String>(username);
    map['password'] = Variable<String>(password);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SybaseConfigsTableCompanion toCompanion(bool nullToAbsent) {
    return SybaseConfigsTableCompanion(
      id: Value(id),
      name: Value(name),
      serverName: Value(serverName),
      databaseName: Value(databaseName),
      databaseFile: Value(databaseFile),
      port: Value(port),
      username: Value(username),
      password: Value(password),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SybaseConfigsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SybaseConfigsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      serverName: serializer.fromJson<String>(json['serverName']),
      databaseName: serializer.fromJson<String>(json['databaseName']),
      databaseFile: serializer.fromJson<String>(json['databaseFile']),
      port: serializer.fromJson<int>(json['port']),
      username: serializer.fromJson<String>(json['username']),
      password: serializer.fromJson<String>(json['password']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'serverName': serializer.toJson<String>(serverName),
      'databaseName': serializer.toJson<String>(databaseName),
      'databaseFile': serializer.toJson<String>(databaseFile),
      'port': serializer.toJson<int>(port),
      'username': serializer.toJson<String>(username),
      'password': serializer.toJson<String>(password),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SybaseConfigsTableData copyWith({
    String? id,
    String? name,
    String? serverName,
    String? databaseName,
    String? databaseFile,
    int? port,
    String? username,
    String? password,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SybaseConfigsTableData(
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
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SybaseConfigsTableData copyWithCompanion(SybaseConfigsTableCompanion data) {
    return SybaseConfigsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      serverName: data.serverName.present
          ? data.serverName.value
          : this.serverName,
      databaseName: data.databaseName.present
          ? data.databaseName.value
          : this.databaseName,
      databaseFile: data.databaseFile.present
          ? data.databaseFile.value
          : this.databaseFile,
      port: data.port.present ? data.port.value : this.port,
      username: data.username.present ? data.username.value : this.username,
      password: data.password.present ? data.password.value : this.password,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SybaseConfigsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('serverName: $serverName, ')
          ..write('databaseName: $databaseName, ')
          ..write('databaseFile: $databaseFile, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    serverName,
    databaseName,
    databaseFile,
    port,
    username,
    password,
    enabled,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SybaseConfigsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.serverName == this.serverName &&
          other.databaseName == this.databaseName &&
          other.databaseFile == this.databaseFile &&
          other.port == this.port &&
          other.username == this.username &&
          other.password == this.password &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SybaseConfigsTableCompanion
    extends UpdateCompanion<SybaseConfigsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> serverName;
  final Value<String> databaseName;
  final Value<String> databaseFile;
  final Value<int> port;
  final Value<String> username;
  final Value<String> password;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SybaseConfigsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.serverName = const Value.absent(),
    this.databaseName = const Value.absent(),
    this.databaseFile = const Value.absent(),
    this.port = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SybaseConfigsTableCompanion.insert({
    required String id,
    required String name,
    required String serverName,
    required String databaseName,
    required String databaseFile,
    this.port = const Value.absent(),
    required String username,
    required String password,
    this.enabled = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       serverName = Value(serverName),
       databaseName = Value(databaseName),
       databaseFile = Value(databaseFile),
       username = Value(username),
       password = Value(password),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SybaseConfigsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? serverName,
    Expression<String>? databaseName,
    Expression<String>? databaseFile,
    Expression<int>? port,
    Expression<String>? username,
    Expression<String>? password,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (serverName != null) 'server_name': serverName,
      if (databaseName != null) 'database_name': databaseName,
      if (databaseFile != null) 'database_file': databaseFile,
      if (port != null) 'port': port,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SybaseConfigsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? serverName,
    Value<String>? databaseName,
    Value<String>? databaseFile,
    Value<int>? port,
    Value<String>? username,
    Value<String>? password,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SybaseConfigsTableCompanion(
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
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (serverName.present) {
      map['server_name'] = Variable<String>(serverName.value);
    }
    if (databaseName.present) {
      map['database_name'] = Variable<String>(databaseName.value);
    }
    if (databaseFile.present) {
      map['database_file'] = Variable<String>(databaseFile.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (password.present) {
      map['password'] = Variable<String>(password.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SybaseConfigsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('serverName: $serverName, ')
          ..write('databaseName: $databaseName, ')
          ..write('databaseFile: $databaseFile, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BackupDestinationsTableTable extends BackupDestinationsTable
    with TableInfo<$BackupDestinationsTableTable, BackupDestinationsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BackupDestinationsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _configMeta = const VerificationMeta('config');
  @override
  late final GeneratedColumn<String> config = GeneratedColumn<String>(
    'config',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    config,
    enabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'backup_destinations_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<BackupDestinationsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('config')) {
      context.handle(
        _configMeta,
        config.isAcceptableOrUnknown(data['config']!, _configMeta),
      );
    } else if (isInserting) {
      context.missing(_configMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BackupDestinationsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BackupDestinationsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      config: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BackupDestinationsTableTable createAlias(String alias) {
    return $BackupDestinationsTableTable(attachedDatabase, alias);
  }
}

class BackupDestinationsTableData extends DataClass
    implements Insertable<BackupDestinationsTableData> {
  final String id;
  final String name;
  final String type;
  final String config;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const BackupDestinationsTableData({
    required this.id,
    required this.name,
    required this.type,
    required this.config,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['config'] = Variable<String>(config);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BackupDestinationsTableCompanion toCompanion(bool nullToAbsent) {
    return BackupDestinationsTableCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      config: Value(config),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BackupDestinationsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BackupDestinationsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      config: serializer.fromJson<String>(json['config']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'config': serializer.toJson<String>(config),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  BackupDestinationsTableData copyWith({
    String? id,
    String? name,
    String? type,
    String? config,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => BackupDestinationsTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    config: config ?? this.config,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BackupDestinationsTableData copyWithCompanion(
    BackupDestinationsTableCompanion data,
  ) {
    return BackupDestinationsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      config: data.config.present ? data.config.value : this.config,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BackupDestinationsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('config: $config, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, type, config, enabled, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BackupDestinationsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.config == this.config &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BackupDestinationsTableCompanion
    extends UpdateCompanion<BackupDestinationsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String> config;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BackupDestinationsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.config = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BackupDestinationsTableCompanion.insert({
    required String id,
    required String name,
    required String type,
    required String config,
    this.enabled = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       type = Value(type),
       config = Value(config),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BackupDestinationsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? config,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (config != null) 'config': config,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BackupDestinationsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? type,
    Value<String>? config,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return BackupDestinationsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      config: config ?? this.config,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (config.present) {
      map['config'] = Variable<String>(config.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BackupDestinationsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('config: $config, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SchedulesTableTable extends SchedulesTable
    with TableInfo<$SchedulesTableTable, SchedulesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchedulesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _databaseConfigIdMeta = const VerificationMeta(
    'databaseConfigId',
  );
  @override
  late final GeneratedColumn<String> databaseConfigId = GeneratedColumn<String>(
    'database_config_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _databaseTypeMeta = const VerificationMeta(
    'databaseType',
  );
  @override
  late final GeneratedColumn<String> databaseType = GeneratedColumn<String>(
    'database_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduleTypeMeta = const VerificationMeta(
    'scheduleType',
  );
  @override
  late final GeneratedColumn<String> scheduleType = GeneratedColumn<String>(
    'schedule_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduleConfigMeta = const VerificationMeta(
    'scheduleConfig',
  );
  @override
  late final GeneratedColumn<String> scheduleConfig = GeneratedColumn<String>(
    'schedule_config',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationIdsMeta = const VerificationMeta(
    'destinationIds',
  );
  @override
  late final GeneratedColumn<String> destinationIds = GeneratedColumn<String>(
    'destination_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backupFolderMeta = const VerificationMeta(
    'backupFolder',
  );
  @override
  late final GeneratedColumn<String> backupFolder = GeneratedColumn<String>(
    'backup_folder',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _backupTypeMeta = const VerificationMeta(
    'backupType',
  );
  @override
  late final GeneratedColumn<String> backupType = GeneratedColumn<String>(
    'backup_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('full'),
  );
  static const VerificationMeta _compressBackupMeta = const VerificationMeta(
    'compressBackup',
  );
  @override
  late final GeneratedColumn<bool> compressBackup = GeneratedColumn<bool>(
    'compress_backup',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("compress_backup" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastRunAtMeta = const VerificationMeta(
    'lastRunAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastRunAt = GeneratedColumn<DateTime>(
    'last_run_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextRunAtMeta = const VerificationMeta(
    'nextRunAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextRunAt = GeneratedColumn<DateTime>(
    'next_run_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    databaseConfigId,
    databaseType,
    scheduleType,
    scheduleConfig,
    destinationIds,
    backupFolder,
    backupType,
    compressBackup,
    enabled,
    lastRunAt,
    nextRunAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedules_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<SchedulesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('database_config_id')) {
      context.handle(
        _databaseConfigIdMeta,
        databaseConfigId.isAcceptableOrUnknown(
          data['database_config_id']!,
          _databaseConfigIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_databaseConfigIdMeta);
    }
    if (data.containsKey('database_type')) {
      context.handle(
        _databaseTypeMeta,
        databaseType.isAcceptableOrUnknown(
          data['database_type']!,
          _databaseTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_databaseTypeMeta);
    }
    if (data.containsKey('schedule_type')) {
      context.handle(
        _scheduleTypeMeta,
        scheduleType.isAcceptableOrUnknown(
          data['schedule_type']!,
          _scheduleTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduleTypeMeta);
    }
    if (data.containsKey('schedule_config')) {
      context.handle(
        _scheduleConfigMeta,
        scheduleConfig.isAcceptableOrUnknown(
          data['schedule_config']!,
          _scheduleConfigMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduleConfigMeta);
    }
    if (data.containsKey('destination_ids')) {
      context.handle(
        _destinationIdsMeta,
        destinationIds.isAcceptableOrUnknown(
          data['destination_ids']!,
          _destinationIdsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_destinationIdsMeta);
    }
    if (data.containsKey('backup_folder')) {
      context.handle(
        _backupFolderMeta,
        backupFolder.isAcceptableOrUnknown(
          data['backup_folder']!,
          _backupFolderMeta,
        ),
      );
    }
    if (data.containsKey('backup_type')) {
      context.handle(
        _backupTypeMeta,
        backupType.isAcceptableOrUnknown(data['backup_type']!, _backupTypeMeta),
      );
    }
    if (data.containsKey('compress_backup')) {
      context.handle(
        _compressBackupMeta,
        compressBackup.isAcceptableOrUnknown(
          data['compress_backup']!,
          _compressBackupMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('last_run_at')) {
      context.handle(
        _lastRunAtMeta,
        lastRunAt.isAcceptableOrUnknown(data['last_run_at']!, _lastRunAtMeta),
      );
    }
    if (data.containsKey('next_run_at')) {
      context.handle(
        _nextRunAtMeta,
        nextRunAt.isAcceptableOrUnknown(data['next_run_at']!, _nextRunAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SchedulesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SchedulesTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      databaseConfigId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}database_config_id'],
      )!,
      databaseType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}database_type'],
      )!,
      scheduleType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_type'],
      )!,
      scheduleConfig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_config'],
      )!,
      destinationIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_ids'],
      )!,
      backupFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backup_folder'],
      )!,
      backupType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backup_type'],
      )!,
      compressBackup: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}compress_backup'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      lastRunAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_run_at'],
      ),
      nextRunAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_run_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SchedulesTableTable createAlias(String alias) {
    return $SchedulesTableTable(attachedDatabase, alias);
  }
}

class SchedulesTableData extends DataClass
    implements Insertable<SchedulesTableData> {
  final String id;
  final String name;
  final String databaseConfigId;
  final String databaseType;
  final String scheduleType;
  final String scheduleConfig;
  final String destinationIds;
  final String backupFolder;
  final String backupType;
  final bool compressBackup;
  final bool enabled;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SchedulesTableData({
    required this.id,
    required this.name,
    required this.databaseConfigId,
    required this.databaseType,
    required this.scheduleType,
    required this.scheduleConfig,
    required this.destinationIds,
    required this.backupFolder,
    required this.backupType,
    required this.compressBackup,
    required this.enabled,
    this.lastRunAt,
    this.nextRunAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['database_config_id'] = Variable<String>(databaseConfigId);
    map['database_type'] = Variable<String>(databaseType);
    map['schedule_type'] = Variable<String>(scheduleType);
    map['schedule_config'] = Variable<String>(scheduleConfig);
    map['destination_ids'] = Variable<String>(destinationIds);
    map['backup_folder'] = Variable<String>(backupFolder);
    map['backup_type'] = Variable<String>(backupType);
    map['compress_backup'] = Variable<bool>(compressBackup);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || lastRunAt != null) {
      map['last_run_at'] = Variable<DateTime>(lastRunAt);
    }
    if (!nullToAbsent || nextRunAt != null) {
      map['next_run_at'] = Variable<DateTime>(nextRunAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SchedulesTableCompanion toCompanion(bool nullToAbsent) {
    return SchedulesTableCompanion(
      id: Value(id),
      name: Value(name),
      databaseConfigId: Value(databaseConfigId),
      databaseType: Value(databaseType),
      scheduleType: Value(scheduleType),
      scheduleConfig: Value(scheduleConfig),
      destinationIds: Value(destinationIds),
      backupFolder: Value(backupFolder),
      backupType: Value(backupType),
      compressBackup: Value(compressBackup),
      enabled: Value(enabled),
      lastRunAt: lastRunAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRunAt),
      nextRunAt: nextRunAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRunAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SchedulesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SchedulesTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      databaseConfigId: serializer.fromJson<String>(json['databaseConfigId']),
      databaseType: serializer.fromJson<String>(json['databaseType']),
      scheduleType: serializer.fromJson<String>(json['scheduleType']),
      scheduleConfig: serializer.fromJson<String>(json['scheduleConfig']),
      destinationIds: serializer.fromJson<String>(json['destinationIds']),
      backupFolder: serializer.fromJson<String>(json['backupFolder']),
      backupType: serializer.fromJson<String>(json['backupType']),
      compressBackup: serializer.fromJson<bool>(json['compressBackup']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      lastRunAt: serializer.fromJson<DateTime?>(json['lastRunAt']),
      nextRunAt: serializer.fromJson<DateTime?>(json['nextRunAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'databaseConfigId': serializer.toJson<String>(databaseConfigId),
      'databaseType': serializer.toJson<String>(databaseType),
      'scheduleType': serializer.toJson<String>(scheduleType),
      'scheduleConfig': serializer.toJson<String>(scheduleConfig),
      'destinationIds': serializer.toJson<String>(destinationIds),
      'backupFolder': serializer.toJson<String>(backupFolder),
      'backupType': serializer.toJson<String>(backupType),
      'compressBackup': serializer.toJson<bool>(compressBackup),
      'enabled': serializer.toJson<bool>(enabled),
      'lastRunAt': serializer.toJson<DateTime?>(lastRunAt),
      'nextRunAt': serializer.toJson<DateTime?>(nextRunAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SchedulesTableData copyWith({
    String? id,
    String? name,
    String? databaseConfigId,
    String? databaseType,
    String? scheduleType,
    String? scheduleConfig,
    String? destinationIds,
    String? backupFolder,
    String? backupType,
    bool? compressBackup,
    bool? enabled,
    Value<DateTime?> lastRunAt = const Value.absent(),
    Value<DateTime?> nextRunAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SchedulesTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    databaseConfigId: databaseConfigId ?? this.databaseConfigId,
    databaseType: databaseType ?? this.databaseType,
    scheduleType: scheduleType ?? this.scheduleType,
    scheduleConfig: scheduleConfig ?? this.scheduleConfig,
    destinationIds: destinationIds ?? this.destinationIds,
    backupFolder: backupFolder ?? this.backupFolder,
    backupType: backupType ?? this.backupType,
    compressBackup: compressBackup ?? this.compressBackup,
    enabled: enabled ?? this.enabled,
    lastRunAt: lastRunAt.present ? lastRunAt.value : this.lastRunAt,
    nextRunAt: nextRunAt.present ? nextRunAt.value : this.nextRunAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SchedulesTableData copyWithCompanion(SchedulesTableCompanion data) {
    return SchedulesTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      databaseConfigId: data.databaseConfigId.present
          ? data.databaseConfigId.value
          : this.databaseConfigId,
      databaseType: data.databaseType.present
          ? data.databaseType.value
          : this.databaseType,
      scheduleType: data.scheduleType.present
          ? data.scheduleType.value
          : this.scheduleType,
      scheduleConfig: data.scheduleConfig.present
          ? data.scheduleConfig.value
          : this.scheduleConfig,
      destinationIds: data.destinationIds.present
          ? data.destinationIds.value
          : this.destinationIds,
      backupFolder: data.backupFolder.present
          ? data.backupFolder.value
          : this.backupFolder,
      backupType: data.backupType.present
          ? data.backupType.value
          : this.backupType,
      compressBackup: data.compressBackup.present
          ? data.compressBackup.value
          : this.compressBackup,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      lastRunAt: data.lastRunAt.present ? data.lastRunAt.value : this.lastRunAt,
      nextRunAt: data.nextRunAt.present ? data.nextRunAt.value : this.nextRunAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SchedulesTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('databaseConfigId: $databaseConfigId, ')
          ..write('databaseType: $databaseType, ')
          ..write('scheduleType: $scheduleType, ')
          ..write('scheduleConfig: $scheduleConfig, ')
          ..write('destinationIds: $destinationIds, ')
          ..write('backupFolder: $backupFolder, ')
          ..write('backupType: $backupType, ')
          ..write('compressBackup: $compressBackup, ')
          ..write('enabled: $enabled, ')
          ..write('lastRunAt: $lastRunAt, ')
          ..write('nextRunAt: $nextRunAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    databaseConfigId,
    databaseType,
    scheduleType,
    scheduleConfig,
    destinationIds,
    backupFolder,
    backupType,
    compressBackup,
    enabled,
    lastRunAt,
    nextRunAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchedulesTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.databaseConfigId == this.databaseConfigId &&
          other.databaseType == this.databaseType &&
          other.scheduleType == this.scheduleType &&
          other.scheduleConfig == this.scheduleConfig &&
          other.destinationIds == this.destinationIds &&
          other.backupFolder == this.backupFolder &&
          other.backupType == this.backupType &&
          other.compressBackup == this.compressBackup &&
          other.enabled == this.enabled &&
          other.lastRunAt == this.lastRunAt &&
          other.nextRunAt == this.nextRunAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SchedulesTableCompanion extends UpdateCompanion<SchedulesTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> databaseConfigId;
  final Value<String> databaseType;
  final Value<String> scheduleType;
  final Value<String> scheduleConfig;
  final Value<String> destinationIds;
  final Value<String> backupFolder;
  final Value<String> backupType;
  final Value<bool> compressBackup;
  final Value<bool> enabled;
  final Value<DateTime?> lastRunAt;
  final Value<DateTime?> nextRunAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SchedulesTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.databaseConfigId = const Value.absent(),
    this.databaseType = const Value.absent(),
    this.scheduleType = const Value.absent(),
    this.scheduleConfig = const Value.absent(),
    this.destinationIds = const Value.absent(),
    this.backupFolder = const Value.absent(),
    this.backupType = const Value.absent(),
    this.compressBackup = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastRunAt = const Value.absent(),
    this.nextRunAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SchedulesTableCompanion.insert({
    required String id,
    required String name,
    required String databaseConfigId,
    required String databaseType,
    required String scheduleType,
    required String scheduleConfig,
    required String destinationIds,
    this.backupFolder = const Value.absent(),
    this.backupType = const Value.absent(),
    this.compressBackup = const Value.absent(),
    this.enabled = const Value.absent(),
    this.lastRunAt = const Value.absent(),
    this.nextRunAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       databaseConfigId = Value(databaseConfigId),
       databaseType = Value(databaseType),
       scheduleType = Value(scheduleType),
       scheduleConfig = Value(scheduleConfig),
       destinationIds = Value(destinationIds),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SchedulesTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? databaseConfigId,
    Expression<String>? databaseType,
    Expression<String>? scheduleType,
    Expression<String>? scheduleConfig,
    Expression<String>? destinationIds,
    Expression<String>? backupFolder,
    Expression<String>? backupType,
    Expression<bool>? compressBackup,
    Expression<bool>? enabled,
    Expression<DateTime>? lastRunAt,
    Expression<DateTime>? nextRunAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (databaseConfigId != null) 'database_config_id': databaseConfigId,
      if (databaseType != null) 'database_type': databaseType,
      if (scheduleType != null) 'schedule_type': scheduleType,
      if (scheduleConfig != null) 'schedule_config': scheduleConfig,
      if (destinationIds != null) 'destination_ids': destinationIds,
      if (backupFolder != null) 'backup_folder': backupFolder,
      if (backupType != null) 'backup_type': backupType,
      if (compressBackup != null) 'compress_backup': compressBackup,
      if (enabled != null) 'enabled': enabled,
      if (lastRunAt != null) 'last_run_at': lastRunAt,
      if (nextRunAt != null) 'next_run_at': nextRunAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SchedulesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? databaseConfigId,
    Value<String>? databaseType,
    Value<String>? scheduleType,
    Value<String>? scheduleConfig,
    Value<String>? destinationIds,
    Value<String>? backupFolder,
    Value<String>? backupType,
    Value<bool>? compressBackup,
    Value<bool>? enabled,
    Value<DateTime?>? lastRunAt,
    Value<DateTime?>? nextRunAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SchedulesTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      databaseConfigId: databaseConfigId ?? this.databaseConfigId,
      databaseType: databaseType ?? this.databaseType,
      scheduleType: scheduleType ?? this.scheduleType,
      scheduleConfig: scheduleConfig ?? this.scheduleConfig,
      destinationIds: destinationIds ?? this.destinationIds,
      backupFolder: backupFolder ?? this.backupFolder,
      backupType: backupType ?? this.backupType,
      compressBackup: compressBackup ?? this.compressBackup,
      enabled: enabled ?? this.enabled,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (databaseConfigId.present) {
      map['database_config_id'] = Variable<String>(databaseConfigId.value);
    }
    if (databaseType.present) {
      map['database_type'] = Variable<String>(databaseType.value);
    }
    if (scheduleType.present) {
      map['schedule_type'] = Variable<String>(scheduleType.value);
    }
    if (scheduleConfig.present) {
      map['schedule_config'] = Variable<String>(scheduleConfig.value);
    }
    if (destinationIds.present) {
      map['destination_ids'] = Variable<String>(destinationIds.value);
    }
    if (backupFolder.present) {
      map['backup_folder'] = Variable<String>(backupFolder.value);
    }
    if (backupType.present) {
      map['backup_type'] = Variable<String>(backupType.value);
    }
    if (compressBackup.present) {
      map['compress_backup'] = Variable<bool>(compressBackup.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (lastRunAt.present) {
      map['last_run_at'] = Variable<DateTime>(lastRunAt.value);
    }
    if (nextRunAt.present) {
      map['next_run_at'] = Variable<DateTime>(nextRunAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchedulesTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('databaseConfigId: $databaseConfigId, ')
          ..write('databaseType: $databaseType, ')
          ..write('scheduleType: $scheduleType, ')
          ..write('scheduleConfig: $scheduleConfig, ')
          ..write('destinationIds: $destinationIds, ')
          ..write('backupFolder: $backupFolder, ')
          ..write('backupType: $backupType, ')
          ..write('compressBackup: $compressBackup, ')
          ..write('enabled: $enabled, ')
          ..write('lastRunAt: $lastRunAt, ')
          ..write('nextRunAt: $nextRunAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BackupHistoryTableTable extends BackupHistoryTable
    with TableInfo<$BackupHistoryTableTable, BackupHistoryTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BackupHistoryTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduleIdMeta = const VerificationMeta(
    'scheduleId',
  );
  @override
  late final GeneratedColumn<String> scheduleId = GeneratedColumn<String>(
    'schedule_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _databaseNameMeta = const VerificationMeta(
    'databaseName',
  );
  @override
  late final GeneratedColumn<String> databaseName = GeneratedColumn<String>(
    'database_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _databaseTypeMeta = const VerificationMeta(
    'databaseType',
  );
  @override
  late final GeneratedColumn<String> databaseType = GeneratedColumn<String>(
    'database_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backupPathMeta = const VerificationMeta(
    'backupPath',
  );
  @override
  late final GeneratedColumn<String> backupPath = GeneratedColumn<String>(
    'backup_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backupTypeMeta = const VerificationMeta(
    'backupType',
  );
  @override
  late final GeneratedColumn<String> backupType = GeneratedColumn<String>(
    'backup_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('full'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    scheduleId,
    databaseName,
    databaseType,
    backupPath,
    fileSize,
    backupType,
    status,
    errorMessage,
    startedAt,
    finishedAt,
    durationSeconds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'backup_history_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<BackupHistoryTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('schedule_id')) {
      context.handle(
        _scheduleIdMeta,
        scheduleId.isAcceptableOrUnknown(data['schedule_id']!, _scheduleIdMeta),
      );
    }
    if (data.containsKey('database_name')) {
      context.handle(
        _databaseNameMeta,
        databaseName.isAcceptableOrUnknown(
          data['database_name']!,
          _databaseNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_databaseNameMeta);
    }
    if (data.containsKey('database_type')) {
      context.handle(
        _databaseTypeMeta,
        databaseType.isAcceptableOrUnknown(
          data['database_type']!,
          _databaseTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_databaseTypeMeta);
    }
    if (data.containsKey('backup_path')) {
      context.handle(
        _backupPathMeta,
        backupPath.isAcceptableOrUnknown(data['backup_path']!, _backupPathMeta),
      );
    } else if (isInserting) {
      context.missing(_backupPathMeta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('backup_type')) {
      context.handle(
        _backupTypeMeta,
        backupType.isAcceptableOrUnknown(data['backup_type']!, _backupTypeMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BackupHistoryTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BackupHistoryTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      scheduleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_id'],
      ),
      databaseName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}database_name'],
      )!,
      databaseType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}database_type'],
      )!,
      backupPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backup_path'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      backupType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backup_type'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      ),
    );
  }

  @override
  $BackupHistoryTableTable createAlias(String alias) {
    return $BackupHistoryTableTable(attachedDatabase, alias);
  }
}

class BackupHistoryTableData extends DataClass
    implements Insertable<BackupHistoryTableData> {
  final String id;
  final String? scheduleId;
  final String databaseName;
  final String databaseType;
  final String backupPath;
  final int fileSize;
  final String backupType;
  final String status;
  final String? errorMessage;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? durationSeconds;
  const BackupHistoryTableData({
    required this.id,
    this.scheduleId,
    required this.databaseName,
    required this.databaseType,
    required this.backupPath,
    required this.fileSize,
    required this.backupType,
    required this.status,
    this.errorMessage,
    required this.startedAt,
    this.finishedAt,
    this.durationSeconds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || scheduleId != null) {
      map['schedule_id'] = Variable<String>(scheduleId);
    }
    map['database_name'] = Variable<String>(databaseName);
    map['database_type'] = Variable<String>(databaseType);
    map['backup_path'] = Variable<String>(backupPath);
    map['file_size'] = Variable<int>(fileSize);
    map['backup_type'] = Variable<String>(backupType);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    return map;
  }

  BackupHistoryTableCompanion toCompanion(bool nullToAbsent) {
    return BackupHistoryTableCompanion(
      id: Value(id),
      scheduleId: scheduleId == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduleId),
      databaseName: Value(databaseName),
      databaseType: Value(databaseType),
      backupPath: Value(backupPath),
      fileSize: Value(fileSize),
      backupType: Value(backupType),
      status: Value(status),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      startedAt: Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      durationSeconds: durationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSeconds),
    );
  }

  factory BackupHistoryTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BackupHistoryTableData(
      id: serializer.fromJson<String>(json['id']),
      scheduleId: serializer.fromJson<String?>(json['scheduleId']),
      databaseName: serializer.fromJson<String>(json['databaseName']),
      databaseType: serializer.fromJson<String>(json['databaseType']),
      backupPath: serializer.fromJson<String>(json['backupPath']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      backupType: serializer.fromJson<String>(json['backupType']),
      status: serializer.fromJson<String>(json['status']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'scheduleId': serializer.toJson<String?>(scheduleId),
      'databaseName': serializer.toJson<String>(databaseName),
      'databaseType': serializer.toJson<String>(databaseType),
      'backupPath': serializer.toJson<String>(backupPath),
      'fileSize': serializer.toJson<int>(fileSize),
      'backupType': serializer.toJson<String>(backupType),
      'status': serializer.toJson<String>(status),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
    };
  }

  BackupHistoryTableData copyWith({
    String? id,
    Value<String?> scheduleId = const Value.absent(),
    String? databaseName,
    String? databaseType,
    String? backupPath,
    int? fileSize,
    String? backupType,
    String? status,
    Value<String?> errorMessage = const Value.absent(),
    DateTime? startedAt,
    Value<DateTime?> finishedAt = const Value.absent(),
    Value<int?> durationSeconds = const Value.absent(),
  }) => BackupHistoryTableData(
    id: id ?? this.id,
    scheduleId: scheduleId.present ? scheduleId.value : this.scheduleId,
    databaseName: databaseName ?? this.databaseName,
    databaseType: databaseType ?? this.databaseType,
    backupPath: backupPath ?? this.backupPath,
    fileSize: fileSize ?? this.fileSize,
    backupType: backupType ?? this.backupType,
    status: status ?? this.status,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    durationSeconds: durationSeconds.present
        ? durationSeconds.value
        : this.durationSeconds,
  );
  BackupHistoryTableData copyWithCompanion(BackupHistoryTableCompanion data) {
    return BackupHistoryTableData(
      id: data.id.present ? data.id.value : this.id,
      scheduleId: data.scheduleId.present
          ? data.scheduleId.value
          : this.scheduleId,
      databaseName: data.databaseName.present
          ? data.databaseName.value
          : this.databaseName,
      databaseType: data.databaseType.present
          ? data.databaseType.value
          : this.databaseType,
      backupPath: data.backupPath.present
          ? data.backupPath.value
          : this.backupPath,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      backupType: data.backupType.present
          ? data.backupType.value
          : this.backupType,
      status: data.status.present ? data.status.value : this.status,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BackupHistoryTableData(')
          ..write('id: $id, ')
          ..write('scheduleId: $scheduleId, ')
          ..write('databaseName: $databaseName, ')
          ..write('databaseType: $databaseType, ')
          ..write('backupPath: $backupPath, ')
          ..write('fileSize: $fileSize, ')
          ..write('backupType: $backupType, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('durationSeconds: $durationSeconds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    scheduleId,
    databaseName,
    databaseType,
    backupPath,
    fileSize,
    backupType,
    status,
    errorMessage,
    startedAt,
    finishedAt,
    durationSeconds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BackupHistoryTableData &&
          other.id == this.id &&
          other.scheduleId == this.scheduleId &&
          other.databaseName == this.databaseName &&
          other.databaseType == this.databaseType &&
          other.backupPath == this.backupPath &&
          other.fileSize == this.fileSize &&
          other.backupType == this.backupType &&
          other.status == this.status &&
          other.errorMessage == this.errorMessage &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt &&
          other.durationSeconds == this.durationSeconds);
}

class BackupHistoryTableCompanion
    extends UpdateCompanion<BackupHistoryTableData> {
  final Value<String> id;
  final Value<String?> scheduleId;
  final Value<String> databaseName;
  final Value<String> databaseType;
  final Value<String> backupPath;
  final Value<int> fileSize;
  final Value<String> backupType;
  final Value<String> status;
  final Value<String?> errorMessage;
  final Value<DateTime> startedAt;
  final Value<DateTime?> finishedAt;
  final Value<int?> durationSeconds;
  final Value<int> rowid;
  const BackupHistoryTableCompanion({
    this.id = const Value.absent(),
    this.scheduleId = const Value.absent(),
    this.databaseName = const Value.absent(),
    this.databaseType = const Value.absent(),
    this.backupPath = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.backupType = const Value.absent(),
    this.status = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BackupHistoryTableCompanion.insert({
    required String id,
    this.scheduleId = const Value.absent(),
    required String databaseName,
    required String databaseType,
    required String backupPath,
    required int fileSize,
    this.backupType = const Value.absent(),
    required String status,
    this.errorMessage = const Value.absent(),
    required DateTime startedAt,
    this.finishedAt = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       databaseName = Value(databaseName),
       databaseType = Value(databaseType),
       backupPath = Value(backupPath),
       fileSize = Value(fileSize),
       status = Value(status),
       startedAt = Value(startedAt);
  static Insertable<BackupHistoryTableData> custom({
    Expression<String>? id,
    Expression<String>? scheduleId,
    Expression<String>? databaseName,
    Expression<String>? databaseType,
    Expression<String>? backupPath,
    Expression<int>? fileSize,
    Expression<String>? backupType,
    Expression<String>? status,
    Expression<String>? errorMessage,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
    Expression<int>? durationSeconds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scheduleId != null) 'schedule_id': scheduleId,
      if (databaseName != null) 'database_name': databaseName,
      if (databaseType != null) 'database_type': databaseType,
      if (backupPath != null) 'backup_path': backupPath,
      if (fileSize != null) 'file_size': fileSize,
      if (backupType != null) 'backup_type': backupType,
      if (status != null) 'status': status,
      if (errorMessage != null) 'error_message': errorMessage,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BackupHistoryTableCompanion copyWith({
    Value<String>? id,
    Value<String?>? scheduleId,
    Value<String>? databaseName,
    Value<String>? databaseType,
    Value<String>? backupPath,
    Value<int>? fileSize,
    Value<String>? backupType,
    Value<String>? status,
    Value<String?>? errorMessage,
    Value<DateTime>? startedAt,
    Value<DateTime?>? finishedAt,
    Value<int?>? durationSeconds,
    Value<int>? rowid,
  }) {
    return BackupHistoryTableCompanion(
      id: id ?? this.id,
      scheduleId: scheduleId ?? this.scheduleId,
      databaseName: databaseName ?? this.databaseName,
      databaseType: databaseType ?? this.databaseType,
      backupPath: backupPath ?? this.backupPath,
      fileSize: fileSize ?? this.fileSize,
      backupType: backupType ?? this.backupType,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (scheduleId.present) {
      map['schedule_id'] = Variable<String>(scheduleId.value);
    }
    if (databaseName.present) {
      map['database_name'] = Variable<String>(databaseName.value);
    }
    if (databaseType.present) {
      map['database_type'] = Variable<String>(databaseType.value);
    }
    if (backupPath.present) {
      map['backup_path'] = Variable<String>(backupPath.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (backupType.present) {
      map['backup_type'] = Variable<String>(backupType.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BackupHistoryTableCompanion(')
          ..write('id: $id, ')
          ..write('scheduleId: $scheduleId, ')
          ..write('databaseName: $databaseName, ')
          ..write('databaseType: $databaseType, ')
          ..write('backupPath: $backupPath, ')
          ..write('fileSize: $fileSize, ')
          ..write('backupType: $backupType, ')
          ..write('status: $status, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BackupLogsTableTable extends BackupLogsTable
    with TableInfo<$BackupLogsTableTable, BackupLogsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BackupLogsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backupHistoryIdMeta = const VerificationMeta(
    'backupHistoryId',
  );
  @override
  late final GeneratedColumn<String> backupHistoryId = GeneratedColumn<String>(
    'backup_history_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailsMeta = const VerificationMeta(
    'details',
  );
  @override
  late final GeneratedColumn<String> details = GeneratedColumn<String>(
    'details',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    backupHistoryId,
    level,
    category,
    message,
    details,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'backup_logs_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<BackupLogsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('backup_history_id')) {
      context.handle(
        _backupHistoryIdMeta,
        backupHistoryId.isAcceptableOrUnknown(
          data['backup_history_id']!,
          _backupHistoryIdMeta,
        ),
      );
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('details')) {
      context.handle(
        _detailsMeta,
        details.isAcceptableOrUnknown(data['details']!, _detailsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BackupLogsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BackupLogsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      backupHistoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backup_history_id'],
      ),
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}level'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      details: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BackupLogsTableTable createAlias(String alias) {
    return $BackupLogsTableTable(attachedDatabase, alias);
  }
}

class BackupLogsTableData extends DataClass
    implements Insertable<BackupLogsTableData> {
  final String id;
  final String? backupHistoryId;
  final String level;
  final String category;
  final String message;
  final String? details;
  final DateTime createdAt;
  const BackupLogsTableData({
    required this.id,
    this.backupHistoryId,
    required this.level,
    required this.category,
    required this.message,
    this.details,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || backupHistoryId != null) {
      map['backup_history_id'] = Variable<String>(backupHistoryId);
    }
    map['level'] = Variable<String>(level);
    map['category'] = Variable<String>(category);
    map['message'] = Variable<String>(message);
    if (!nullToAbsent || details != null) {
      map['details'] = Variable<String>(details);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  BackupLogsTableCompanion toCompanion(bool nullToAbsent) {
    return BackupLogsTableCompanion(
      id: Value(id),
      backupHistoryId: backupHistoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(backupHistoryId),
      level: Value(level),
      category: Value(category),
      message: Value(message),
      details: details == null && nullToAbsent
          ? const Value.absent()
          : Value(details),
      createdAt: Value(createdAt),
    );
  }

  factory BackupLogsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BackupLogsTableData(
      id: serializer.fromJson<String>(json['id']),
      backupHistoryId: serializer.fromJson<String?>(json['backupHistoryId']),
      level: serializer.fromJson<String>(json['level']),
      category: serializer.fromJson<String>(json['category']),
      message: serializer.fromJson<String>(json['message']),
      details: serializer.fromJson<String?>(json['details']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'backupHistoryId': serializer.toJson<String?>(backupHistoryId),
      'level': serializer.toJson<String>(level),
      'category': serializer.toJson<String>(category),
      'message': serializer.toJson<String>(message),
      'details': serializer.toJson<String?>(details),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  BackupLogsTableData copyWith({
    String? id,
    Value<String?> backupHistoryId = const Value.absent(),
    String? level,
    String? category,
    String? message,
    Value<String?> details = const Value.absent(),
    DateTime? createdAt,
  }) => BackupLogsTableData(
    id: id ?? this.id,
    backupHistoryId: backupHistoryId.present
        ? backupHistoryId.value
        : this.backupHistoryId,
    level: level ?? this.level,
    category: category ?? this.category,
    message: message ?? this.message,
    details: details.present ? details.value : this.details,
    createdAt: createdAt ?? this.createdAt,
  );
  BackupLogsTableData copyWithCompanion(BackupLogsTableCompanion data) {
    return BackupLogsTableData(
      id: data.id.present ? data.id.value : this.id,
      backupHistoryId: data.backupHistoryId.present
          ? data.backupHistoryId.value
          : this.backupHistoryId,
      level: data.level.present ? data.level.value : this.level,
      category: data.category.present ? data.category.value : this.category,
      message: data.message.present ? data.message.value : this.message,
      details: data.details.present ? data.details.value : this.details,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BackupLogsTableData(')
          ..write('id: $id, ')
          ..write('backupHistoryId: $backupHistoryId, ')
          ..write('level: $level, ')
          ..write('category: $category, ')
          ..write('message: $message, ')
          ..write('details: $details, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    backupHistoryId,
    level,
    category,
    message,
    details,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BackupLogsTableData &&
          other.id == this.id &&
          other.backupHistoryId == this.backupHistoryId &&
          other.level == this.level &&
          other.category == this.category &&
          other.message == this.message &&
          other.details == this.details &&
          other.createdAt == this.createdAt);
}

class BackupLogsTableCompanion extends UpdateCompanion<BackupLogsTableData> {
  final Value<String> id;
  final Value<String?> backupHistoryId;
  final Value<String> level;
  final Value<String> category;
  final Value<String> message;
  final Value<String?> details;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const BackupLogsTableCompanion({
    this.id = const Value.absent(),
    this.backupHistoryId = const Value.absent(),
    this.level = const Value.absent(),
    this.category = const Value.absent(),
    this.message = const Value.absent(),
    this.details = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BackupLogsTableCompanion.insert({
    required String id,
    this.backupHistoryId = const Value.absent(),
    required String level,
    required String category,
    required String message,
    this.details = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       level = Value(level),
       category = Value(category),
       message = Value(message),
       createdAt = Value(createdAt);
  static Insertable<BackupLogsTableData> custom({
    Expression<String>? id,
    Expression<String>? backupHistoryId,
    Expression<String>? level,
    Expression<String>? category,
    Expression<String>? message,
    Expression<String>? details,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (backupHistoryId != null) 'backup_history_id': backupHistoryId,
      if (level != null) 'level': level,
      if (category != null) 'category': category,
      if (message != null) 'message': message,
      if (details != null) 'details': details,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BackupLogsTableCompanion copyWith({
    Value<String>? id,
    Value<String?>? backupHistoryId,
    Value<String>? level,
    Value<String>? category,
    Value<String>? message,
    Value<String?>? details,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return BackupLogsTableCompanion(
      id: id ?? this.id,
      backupHistoryId: backupHistoryId ?? this.backupHistoryId,
      level: level ?? this.level,
      category: category ?? this.category,
      message: message ?? this.message,
      details: details ?? this.details,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (backupHistoryId.present) {
      map['backup_history_id'] = Variable<String>(backupHistoryId.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (details.present) {
      map['details'] = Variable<String>(details.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BackupLogsTableCompanion(')
          ..write('id: $id, ')
          ..write('backupHistoryId: $backupHistoryId, ')
          ..write('level: $level, ')
          ..write('category: $category, ')
          ..write('message: $message, ')
          ..write('details: $details, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EmailConfigsTableTable extends EmailConfigsTable
    with TableInfo<$EmailConfigsTableTable, EmailConfigsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmailConfigsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderNameMeta = const VerificationMeta(
    'senderName',
  );
  @override
  late final GeneratedColumn<String> senderName = GeneratedColumn<String>(
    'sender_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Sistema de Backup'),
  );
  static const VerificationMeta _fromEmailMeta = const VerificationMeta(
    'fromEmail',
  );
  @override
  late final GeneratedColumn<String> fromEmail = GeneratedColumn<String>(
    'from_email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('backup@example.com'),
  );
  static const VerificationMeta _fromNameMeta = const VerificationMeta(
    'fromName',
  );
  @override
  late final GeneratedColumn<String> fromName = GeneratedColumn<String>(
    'from_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Sistema de Backup'),
  );
  static const VerificationMeta _smtpServerMeta = const VerificationMeta(
    'smtpServer',
  );
  @override
  late final GeneratedColumn<String> smtpServer = GeneratedColumn<String>(
    'smtp_server',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('smtp.gmail.com'),
  );
  static const VerificationMeta _smtpPortMeta = const VerificationMeta(
    'smtpPort',
  );
  @override
  late final GeneratedColumn<int> smtpPort = GeneratedColumn<int>(
    'smtp_port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(587),
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _passwordMeta = const VerificationMeta(
    'password',
  );
  @override
  late final GeneratedColumn<String> password = GeneratedColumn<String>(
    'password',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _useSslMeta = const VerificationMeta('useSsl');
  @override
  late final GeneratedColumn<bool> useSsl = GeneratedColumn<bool>(
    'use_ssl',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("use_ssl" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _recipientsMeta = const VerificationMeta(
    'recipients',
  );
  @override
  late final GeneratedColumn<String> recipients = GeneratedColumn<String>(
    'recipients',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _notifyOnSuccessMeta = const VerificationMeta(
    'notifyOnSuccess',
  );
  @override
  late final GeneratedColumn<bool> notifyOnSuccess = GeneratedColumn<bool>(
    'notify_on_success',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("notify_on_success" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _notifyOnErrorMeta = const VerificationMeta(
    'notifyOnError',
  );
  @override
  late final GeneratedColumn<bool> notifyOnError = GeneratedColumn<bool>(
    'notify_on_error',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("notify_on_error" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _notifyOnWarningMeta = const VerificationMeta(
    'notifyOnWarning',
  );
  @override
  late final GeneratedColumn<bool> notifyOnWarning = GeneratedColumn<bool>(
    'notify_on_warning',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("notify_on_warning" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _attachLogMeta = const VerificationMeta(
    'attachLog',
  );
  @override
  late final GeneratedColumn<bool> attachLog = GeneratedColumn<bool>(
    'attach_log',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("attach_log" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    senderName,
    fromEmail,
    fromName,
    smtpServer,
    smtpPort,
    username,
    password,
    useSsl,
    recipients,
    notifyOnSuccess,
    notifyOnError,
    notifyOnWarning,
    attachLog,
    enabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'email_configs_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<EmailConfigsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sender_name')) {
      context.handle(
        _senderNameMeta,
        senderName.isAcceptableOrUnknown(data['sender_name']!, _senderNameMeta),
      );
    }
    if (data.containsKey('from_email')) {
      context.handle(
        _fromEmailMeta,
        fromEmail.isAcceptableOrUnknown(data['from_email']!, _fromEmailMeta),
      );
    }
    if (data.containsKey('from_name')) {
      context.handle(
        _fromNameMeta,
        fromName.isAcceptableOrUnknown(data['from_name']!, _fromNameMeta),
      );
    }
    if (data.containsKey('smtp_server')) {
      context.handle(
        _smtpServerMeta,
        smtpServer.isAcceptableOrUnknown(data['smtp_server']!, _smtpServerMeta),
      );
    }
    if (data.containsKey('smtp_port')) {
      context.handle(
        _smtpPortMeta,
        smtpPort.isAcceptableOrUnknown(data['smtp_port']!, _smtpPortMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('password')) {
      context.handle(
        _passwordMeta,
        password.isAcceptableOrUnknown(data['password']!, _passwordMeta),
      );
    }
    if (data.containsKey('use_ssl')) {
      context.handle(
        _useSslMeta,
        useSsl.isAcceptableOrUnknown(data['use_ssl']!, _useSslMeta),
      );
    }
    if (data.containsKey('recipients')) {
      context.handle(
        _recipientsMeta,
        recipients.isAcceptableOrUnknown(data['recipients']!, _recipientsMeta),
      );
    }
    if (data.containsKey('notify_on_success')) {
      context.handle(
        _notifyOnSuccessMeta,
        notifyOnSuccess.isAcceptableOrUnknown(
          data['notify_on_success']!,
          _notifyOnSuccessMeta,
        ),
      );
    }
    if (data.containsKey('notify_on_error')) {
      context.handle(
        _notifyOnErrorMeta,
        notifyOnError.isAcceptableOrUnknown(
          data['notify_on_error']!,
          _notifyOnErrorMeta,
        ),
      );
    }
    if (data.containsKey('notify_on_warning')) {
      context.handle(
        _notifyOnWarningMeta,
        notifyOnWarning.isAcceptableOrUnknown(
          data['notify_on_warning']!,
          _notifyOnWarningMeta,
        ),
      );
    }
    if (data.containsKey('attach_log')) {
      context.handle(
        _attachLogMeta,
        attachLog.isAcceptableOrUnknown(data['attach_log']!, _attachLogMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EmailConfigsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EmailConfigsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      senderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_name'],
      )!,
      fromEmail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_email'],
      )!,
      fromName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_name'],
      )!,
      smtpServer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}smtp_server'],
      )!,
      smtpPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}smtp_port'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      password: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password'],
      )!,
      useSsl: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}use_ssl'],
      )!,
      recipients: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipients'],
      )!,
      notifyOnSuccess: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}notify_on_success'],
      )!,
      notifyOnError: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}notify_on_error'],
      )!,
      notifyOnWarning: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}notify_on_warning'],
      )!,
      attachLog: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}attach_log'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EmailConfigsTableTable createAlias(String alias) {
    return $EmailConfigsTableTable(attachedDatabase, alias);
  }
}

class EmailConfigsTableData extends DataClass
    implements Insertable<EmailConfigsTableData> {
  final String id;
  final String senderName;
  final String fromEmail;
  final String fromName;
  final String smtpServer;
  final int smtpPort;
  final String username;
  final String password;
  final bool useSsl;
  final String recipients;
  final bool notifyOnSuccess;
  final bool notifyOnError;
  final bool notifyOnWarning;
  final bool attachLog;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const EmailConfigsTableData({
    required this.id,
    required this.senderName,
    required this.fromEmail,
    required this.fromName,
    required this.smtpServer,
    required this.smtpPort,
    required this.username,
    required this.password,
    required this.useSsl,
    required this.recipients,
    required this.notifyOnSuccess,
    required this.notifyOnError,
    required this.notifyOnWarning,
    required this.attachLog,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sender_name'] = Variable<String>(senderName);
    map['from_email'] = Variable<String>(fromEmail);
    map['from_name'] = Variable<String>(fromName);
    map['smtp_server'] = Variable<String>(smtpServer);
    map['smtp_port'] = Variable<int>(smtpPort);
    map['username'] = Variable<String>(username);
    map['password'] = Variable<String>(password);
    map['use_ssl'] = Variable<bool>(useSsl);
    map['recipients'] = Variable<String>(recipients);
    map['notify_on_success'] = Variable<bool>(notifyOnSuccess);
    map['notify_on_error'] = Variable<bool>(notifyOnError);
    map['notify_on_warning'] = Variable<bool>(notifyOnWarning);
    map['attach_log'] = Variable<bool>(attachLog);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EmailConfigsTableCompanion toCompanion(bool nullToAbsent) {
    return EmailConfigsTableCompanion(
      id: Value(id),
      senderName: Value(senderName),
      fromEmail: Value(fromEmail),
      fromName: Value(fromName),
      smtpServer: Value(smtpServer),
      smtpPort: Value(smtpPort),
      username: Value(username),
      password: Value(password),
      useSsl: Value(useSsl),
      recipients: Value(recipients),
      notifyOnSuccess: Value(notifyOnSuccess),
      notifyOnError: Value(notifyOnError),
      notifyOnWarning: Value(notifyOnWarning),
      attachLog: Value(attachLog),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory EmailConfigsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EmailConfigsTableData(
      id: serializer.fromJson<String>(json['id']),
      senderName: serializer.fromJson<String>(json['senderName']),
      fromEmail: serializer.fromJson<String>(json['fromEmail']),
      fromName: serializer.fromJson<String>(json['fromName']),
      smtpServer: serializer.fromJson<String>(json['smtpServer']),
      smtpPort: serializer.fromJson<int>(json['smtpPort']),
      username: serializer.fromJson<String>(json['username']),
      password: serializer.fromJson<String>(json['password']),
      useSsl: serializer.fromJson<bool>(json['useSsl']),
      recipients: serializer.fromJson<String>(json['recipients']),
      notifyOnSuccess: serializer.fromJson<bool>(json['notifyOnSuccess']),
      notifyOnError: serializer.fromJson<bool>(json['notifyOnError']),
      notifyOnWarning: serializer.fromJson<bool>(json['notifyOnWarning']),
      attachLog: serializer.fromJson<bool>(json['attachLog']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'senderName': serializer.toJson<String>(senderName),
      'fromEmail': serializer.toJson<String>(fromEmail),
      'fromName': serializer.toJson<String>(fromName),
      'smtpServer': serializer.toJson<String>(smtpServer),
      'smtpPort': serializer.toJson<int>(smtpPort),
      'username': serializer.toJson<String>(username),
      'password': serializer.toJson<String>(password),
      'useSsl': serializer.toJson<bool>(useSsl),
      'recipients': serializer.toJson<String>(recipients),
      'notifyOnSuccess': serializer.toJson<bool>(notifyOnSuccess),
      'notifyOnError': serializer.toJson<bool>(notifyOnError),
      'notifyOnWarning': serializer.toJson<bool>(notifyOnWarning),
      'attachLog': serializer.toJson<bool>(attachLog),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  EmailConfigsTableData copyWith({
    String? id,
    String? senderName,
    String? fromEmail,
    String? fromName,
    String? smtpServer,
    int? smtpPort,
    String? username,
    String? password,
    bool? useSsl,
    String? recipients,
    bool? notifyOnSuccess,
    bool? notifyOnError,
    bool? notifyOnWarning,
    bool? attachLog,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => EmailConfigsTableData(
    id: id ?? this.id,
    senderName: senderName ?? this.senderName,
    fromEmail: fromEmail ?? this.fromEmail,
    fromName: fromName ?? this.fromName,
    smtpServer: smtpServer ?? this.smtpServer,
    smtpPort: smtpPort ?? this.smtpPort,
    username: username ?? this.username,
    password: password ?? this.password,
    useSsl: useSsl ?? this.useSsl,
    recipients: recipients ?? this.recipients,
    notifyOnSuccess: notifyOnSuccess ?? this.notifyOnSuccess,
    notifyOnError: notifyOnError ?? this.notifyOnError,
    notifyOnWarning: notifyOnWarning ?? this.notifyOnWarning,
    attachLog: attachLog ?? this.attachLog,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EmailConfigsTableData copyWithCompanion(EmailConfigsTableCompanion data) {
    return EmailConfigsTableData(
      id: data.id.present ? data.id.value : this.id,
      senderName: data.senderName.present
          ? data.senderName.value
          : this.senderName,
      fromEmail: data.fromEmail.present ? data.fromEmail.value : this.fromEmail,
      fromName: data.fromName.present ? data.fromName.value : this.fromName,
      smtpServer: data.smtpServer.present
          ? data.smtpServer.value
          : this.smtpServer,
      smtpPort: data.smtpPort.present ? data.smtpPort.value : this.smtpPort,
      username: data.username.present ? data.username.value : this.username,
      password: data.password.present ? data.password.value : this.password,
      useSsl: data.useSsl.present ? data.useSsl.value : this.useSsl,
      recipients: data.recipients.present
          ? data.recipients.value
          : this.recipients,
      notifyOnSuccess: data.notifyOnSuccess.present
          ? data.notifyOnSuccess.value
          : this.notifyOnSuccess,
      notifyOnError: data.notifyOnError.present
          ? data.notifyOnError.value
          : this.notifyOnError,
      notifyOnWarning: data.notifyOnWarning.present
          ? data.notifyOnWarning.value
          : this.notifyOnWarning,
      attachLog: data.attachLog.present ? data.attachLog.value : this.attachLog,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EmailConfigsTableData(')
          ..write('id: $id, ')
          ..write('senderName: $senderName, ')
          ..write('fromEmail: $fromEmail, ')
          ..write('fromName: $fromName, ')
          ..write('smtpServer: $smtpServer, ')
          ..write('smtpPort: $smtpPort, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('useSsl: $useSsl, ')
          ..write('recipients: $recipients, ')
          ..write('notifyOnSuccess: $notifyOnSuccess, ')
          ..write('notifyOnError: $notifyOnError, ')
          ..write('notifyOnWarning: $notifyOnWarning, ')
          ..write('attachLog: $attachLog, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    senderName,
    fromEmail,
    fromName,
    smtpServer,
    smtpPort,
    username,
    password,
    useSsl,
    recipients,
    notifyOnSuccess,
    notifyOnError,
    notifyOnWarning,
    attachLog,
    enabled,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmailConfigsTableData &&
          other.id == this.id &&
          other.senderName == this.senderName &&
          other.fromEmail == this.fromEmail &&
          other.fromName == this.fromName &&
          other.smtpServer == this.smtpServer &&
          other.smtpPort == this.smtpPort &&
          other.username == this.username &&
          other.password == this.password &&
          other.useSsl == this.useSsl &&
          other.recipients == this.recipients &&
          other.notifyOnSuccess == this.notifyOnSuccess &&
          other.notifyOnError == this.notifyOnError &&
          other.notifyOnWarning == this.notifyOnWarning &&
          other.attachLog == this.attachLog &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class EmailConfigsTableCompanion
    extends UpdateCompanion<EmailConfigsTableData> {
  final Value<String> id;
  final Value<String> senderName;
  final Value<String> fromEmail;
  final Value<String> fromName;
  final Value<String> smtpServer;
  final Value<int> smtpPort;
  final Value<String> username;
  final Value<String> password;
  final Value<bool> useSsl;
  final Value<String> recipients;
  final Value<bool> notifyOnSuccess;
  final Value<bool> notifyOnError;
  final Value<bool> notifyOnWarning;
  final Value<bool> attachLog;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const EmailConfigsTableCompanion({
    this.id = const Value.absent(),
    this.senderName = const Value.absent(),
    this.fromEmail = const Value.absent(),
    this.fromName = const Value.absent(),
    this.smtpServer = const Value.absent(),
    this.smtpPort = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.useSsl = const Value.absent(),
    this.recipients = const Value.absent(),
    this.notifyOnSuccess = const Value.absent(),
    this.notifyOnError = const Value.absent(),
    this.notifyOnWarning = const Value.absent(),
    this.attachLog = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EmailConfigsTableCompanion.insert({
    required String id,
    this.senderName = const Value.absent(),
    this.fromEmail = const Value.absent(),
    this.fromName = const Value.absent(),
    this.smtpServer = const Value.absent(),
    this.smtpPort = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.useSsl = const Value.absent(),
    this.recipients = const Value.absent(),
    this.notifyOnSuccess = const Value.absent(),
    this.notifyOnError = const Value.absent(),
    this.notifyOnWarning = const Value.absent(),
    this.attachLog = const Value.absent(),
    this.enabled = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<EmailConfigsTableData> custom({
    Expression<String>? id,
    Expression<String>? senderName,
    Expression<String>? fromEmail,
    Expression<String>? fromName,
    Expression<String>? smtpServer,
    Expression<int>? smtpPort,
    Expression<String>? username,
    Expression<String>? password,
    Expression<bool>? useSsl,
    Expression<String>? recipients,
    Expression<bool>? notifyOnSuccess,
    Expression<bool>? notifyOnError,
    Expression<bool>? notifyOnWarning,
    Expression<bool>? attachLog,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (senderName != null) 'sender_name': senderName,
      if (fromEmail != null) 'from_email': fromEmail,
      if (fromName != null) 'from_name': fromName,
      if (smtpServer != null) 'smtp_server': smtpServer,
      if (smtpPort != null) 'smtp_port': smtpPort,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (useSsl != null) 'use_ssl': useSsl,
      if (recipients != null) 'recipients': recipients,
      if (notifyOnSuccess != null) 'notify_on_success': notifyOnSuccess,
      if (notifyOnError != null) 'notify_on_error': notifyOnError,
      if (notifyOnWarning != null) 'notify_on_warning': notifyOnWarning,
      if (attachLog != null) 'attach_log': attachLog,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EmailConfigsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? senderName,
    Value<String>? fromEmail,
    Value<String>? fromName,
    Value<String>? smtpServer,
    Value<int>? smtpPort,
    Value<String>? username,
    Value<String>? password,
    Value<bool>? useSsl,
    Value<String>? recipients,
    Value<bool>? notifyOnSuccess,
    Value<bool>? notifyOnError,
    Value<bool>? notifyOnWarning,
    Value<bool>? attachLog,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return EmailConfigsTableCompanion(
      id: id ?? this.id,
      senderName: senderName ?? this.senderName,
      fromEmail: fromEmail ?? this.fromEmail,
      fromName: fromName ?? this.fromName,
      smtpServer: smtpServer ?? this.smtpServer,
      smtpPort: smtpPort ?? this.smtpPort,
      username: username ?? this.username,
      password: password ?? this.password,
      useSsl: useSsl ?? this.useSsl,
      recipients: recipients ?? this.recipients,
      notifyOnSuccess: notifyOnSuccess ?? this.notifyOnSuccess,
      notifyOnError: notifyOnError ?? this.notifyOnError,
      notifyOnWarning: notifyOnWarning ?? this.notifyOnWarning,
      attachLog: attachLog ?? this.attachLog,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (senderName.present) {
      map['sender_name'] = Variable<String>(senderName.value);
    }
    if (fromEmail.present) {
      map['from_email'] = Variable<String>(fromEmail.value);
    }
    if (fromName.present) {
      map['from_name'] = Variable<String>(fromName.value);
    }
    if (smtpServer.present) {
      map['smtp_server'] = Variable<String>(smtpServer.value);
    }
    if (smtpPort.present) {
      map['smtp_port'] = Variable<int>(smtpPort.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (password.present) {
      map['password'] = Variable<String>(password.value);
    }
    if (useSsl.present) {
      map['use_ssl'] = Variable<bool>(useSsl.value);
    }
    if (recipients.present) {
      map['recipients'] = Variable<String>(recipients.value);
    }
    if (notifyOnSuccess.present) {
      map['notify_on_success'] = Variable<bool>(notifyOnSuccess.value);
    }
    if (notifyOnError.present) {
      map['notify_on_error'] = Variable<bool>(notifyOnError.value);
    }
    if (notifyOnWarning.present) {
      map['notify_on_warning'] = Variable<bool>(notifyOnWarning.value);
    }
    if (attachLog.present) {
      map['attach_log'] = Variable<bool>(attachLog.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmailConfigsTableCompanion(')
          ..write('id: $id, ')
          ..write('senderName: $senderName, ')
          ..write('fromEmail: $fromEmail, ')
          ..write('fromName: $fromName, ')
          ..write('smtpServer: $smtpServer, ')
          ..write('smtpPort: $smtpPort, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('useSsl: $useSsl, ')
          ..write('recipients: $recipients, ')
          ..write('notifyOnSuccess: $notifyOnSuccess, ')
          ..write('notifyOnError: $notifyOnError, ')
          ..write('notifyOnWarning: $notifyOnWarning, ')
          ..write('attachLog: $attachLog, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SqlServerConfigsTableTable sqlServerConfigsTable =
      $SqlServerConfigsTableTable(this);
  late final $SybaseConfigsTableTable sybaseConfigsTable =
      $SybaseConfigsTableTable(this);
  late final $BackupDestinationsTableTable backupDestinationsTable =
      $BackupDestinationsTableTable(this);
  late final $SchedulesTableTable schedulesTable = $SchedulesTableTable(this);
  late final $BackupHistoryTableTable backupHistoryTable =
      $BackupHistoryTableTable(this);
  late final $BackupLogsTableTable backupLogsTable = $BackupLogsTableTable(
    this,
  );
  late final $EmailConfigsTableTable emailConfigsTable =
      $EmailConfigsTableTable(this);
  late final SqlServerConfigDao sqlServerConfigDao = SqlServerConfigDao(
    this as AppDatabase,
  );
  late final SybaseConfigDao sybaseConfigDao = SybaseConfigDao(
    this as AppDatabase,
  );
  late final BackupDestinationDao backupDestinationDao = BackupDestinationDao(
    this as AppDatabase,
  );
  late final ScheduleDao scheduleDao = ScheduleDao(this as AppDatabase);
  late final BackupHistoryDao backupHistoryDao = BackupHistoryDao(
    this as AppDatabase,
  );
  late final BackupLogDao backupLogDao = BackupLogDao(this as AppDatabase);
  late final EmailConfigDao emailConfigDao = EmailConfigDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sqlServerConfigsTable,
    sybaseConfigsTable,
    backupDestinationsTable,
    schedulesTable,
    backupHistoryTable,
    backupLogsTable,
    emailConfigsTable,
  ];
}

typedef $$SqlServerConfigsTableTableCreateCompanionBuilder =
    SqlServerConfigsTableCompanion Function({
      required String id,
      required String name,
      required String server,
      required String database,
      required String username,
      required String password,
      Value<int> port,
      Value<bool> enabled,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SqlServerConfigsTableTableUpdateCompanionBuilder =
    SqlServerConfigsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> server,
      Value<String> database,
      Value<String> username,
      Value<String> password,
      Value<int> port,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SqlServerConfigsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SqlServerConfigsTableTable> {
  $$SqlServerConfigsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get database => $composableBuilder(
    column: $table.database,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SqlServerConfigsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SqlServerConfigsTableTable> {
  $$SqlServerConfigsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get database => $composableBuilder(
    column: $table.database,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SqlServerConfigsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SqlServerConfigsTableTable> {
  $$SqlServerConfigsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get server =>
      $composableBuilder(column: $table.server, builder: (column) => column);

  GeneratedColumn<String> get database =>
      $composableBuilder(column: $table.database, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get password =>
      $composableBuilder(column: $table.password, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SqlServerConfigsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SqlServerConfigsTableTable,
          SqlServerConfigsTableData,
          $$SqlServerConfigsTableTableFilterComposer,
          $$SqlServerConfigsTableTableOrderingComposer,
          $$SqlServerConfigsTableTableAnnotationComposer,
          $$SqlServerConfigsTableTableCreateCompanionBuilder,
          $$SqlServerConfigsTableTableUpdateCompanionBuilder,
          (
            SqlServerConfigsTableData,
            BaseReferences<
              _$AppDatabase,
              $SqlServerConfigsTableTable,
              SqlServerConfigsTableData
            >,
          ),
          SqlServerConfigsTableData,
          PrefetchHooks Function()
        > {
  $$SqlServerConfigsTableTableTableManager(
    _$AppDatabase db,
    $SqlServerConfigsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SqlServerConfigsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SqlServerConfigsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SqlServerConfigsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> server = const Value.absent(),
                Value<String> database = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> password = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SqlServerConfigsTableCompanion(
                id: id,
                name: name,
                server: server,
                database: database,
                username: username,
                password: password,
                port: port,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String server,
                required String database,
                required String username,
                required String password,
                Value<int> port = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SqlServerConfigsTableCompanion.insert(
                id: id,
                name: name,
                server: server,
                database: database,
                username: username,
                password: password,
                port: port,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SqlServerConfigsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SqlServerConfigsTableTable,
      SqlServerConfigsTableData,
      $$SqlServerConfigsTableTableFilterComposer,
      $$SqlServerConfigsTableTableOrderingComposer,
      $$SqlServerConfigsTableTableAnnotationComposer,
      $$SqlServerConfigsTableTableCreateCompanionBuilder,
      $$SqlServerConfigsTableTableUpdateCompanionBuilder,
      (
        SqlServerConfigsTableData,
        BaseReferences<
          _$AppDatabase,
          $SqlServerConfigsTableTable,
          SqlServerConfigsTableData
        >,
      ),
      SqlServerConfigsTableData,
      PrefetchHooks Function()
    >;
typedef $$SybaseConfigsTableTableCreateCompanionBuilder =
    SybaseConfigsTableCompanion Function({
      required String id,
      required String name,
      required String serverName,
      required String databaseName,
      required String databaseFile,
      Value<int> port,
      required String username,
      required String password,
      Value<bool> enabled,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SybaseConfigsTableTableUpdateCompanionBuilder =
    SybaseConfigsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> serverName,
      Value<String> databaseName,
      Value<String> databaseFile,
      Value<int> port,
      Value<String> username,
      Value<String> password,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SybaseConfigsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SybaseConfigsTableTable> {
  $$SybaseConfigsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverName => $composableBuilder(
    column: $table.serverName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get databaseName => $composableBuilder(
    column: $table.databaseName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get databaseFile => $composableBuilder(
    column: $table.databaseFile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SybaseConfigsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SybaseConfigsTableTable> {
  $$SybaseConfigsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverName => $composableBuilder(
    column: $table.serverName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get databaseName => $composableBuilder(
    column: $table.databaseName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get databaseFile => $composableBuilder(
    column: $table.databaseFile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SybaseConfigsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SybaseConfigsTableTable> {
  $$SybaseConfigsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get serverName => $composableBuilder(
    column: $table.serverName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get databaseName => $composableBuilder(
    column: $table.databaseName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get databaseFile => $composableBuilder(
    column: $table.databaseFile,
    builder: (column) => column,
  );

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get password =>
      $composableBuilder(column: $table.password, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SybaseConfigsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SybaseConfigsTableTable,
          SybaseConfigsTableData,
          $$SybaseConfigsTableTableFilterComposer,
          $$SybaseConfigsTableTableOrderingComposer,
          $$SybaseConfigsTableTableAnnotationComposer,
          $$SybaseConfigsTableTableCreateCompanionBuilder,
          $$SybaseConfigsTableTableUpdateCompanionBuilder,
          (
            SybaseConfigsTableData,
            BaseReferences<
              _$AppDatabase,
              $SybaseConfigsTableTable,
              SybaseConfigsTableData
            >,
          ),
          SybaseConfigsTableData,
          PrefetchHooks Function()
        > {
  $$SybaseConfigsTableTableTableManager(
    _$AppDatabase db,
    $SybaseConfigsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SybaseConfigsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SybaseConfigsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SybaseConfigsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> serverName = const Value.absent(),
                Value<String> databaseName = const Value.absent(),
                Value<String> databaseFile = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> password = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SybaseConfigsTableCompanion(
                id: id,
                name: name,
                serverName: serverName,
                databaseName: databaseName,
                databaseFile: databaseFile,
                port: port,
                username: username,
                password: password,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String serverName,
                required String databaseName,
                required String databaseFile,
                Value<int> port = const Value.absent(),
                required String username,
                required String password,
                Value<bool> enabled = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SybaseConfigsTableCompanion.insert(
                id: id,
                name: name,
                serverName: serverName,
                databaseName: databaseName,
                databaseFile: databaseFile,
                port: port,
                username: username,
                password: password,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SybaseConfigsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SybaseConfigsTableTable,
      SybaseConfigsTableData,
      $$SybaseConfigsTableTableFilterComposer,
      $$SybaseConfigsTableTableOrderingComposer,
      $$SybaseConfigsTableTableAnnotationComposer,
      $$SybaseConfigsTableTableCreateCompanionBuilder,
      $$SybaseConfigsTableTableUpdateCompanionBuilder,
      (
        SybaseConfigsTableData,
        BaseReferences<
          _$AppDatabase,
          $SybaseConfigsTableTable,
          SybaseConfigsTableData
        >,
      ),
      SybaseConfigsTableData,
      PrefetchHooks Function()
    >;
typedef $$BackupDestinationsTableTableCreateCompanionBuilder =
    BackupDestinationsTableCompanion Function({
      required String id,
      required String name,
      required String type,
      required String config,
      Value<bool> enabled,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$BackupDestinationsTableTableUpdateCompanionBuilder =
    BackupDestinationsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> type,
      Value<String> config,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$BackupDestinationsTableTableFilterComposer
    extends Composer<_$AppDatabase, $BackupDestinationsTableTable> {
  $$BackupDestinationsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get config => $composableBuilder(
    column: $table.config,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BackupDestinationsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $BackupDestinationsTableTable> {
  $$BackupDestinationsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get config => $composableBuilder(
    column: $table.config,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BackupDestinationsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $BackupDestinationsTableTable> {
  $$BackupDestinationsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get config =>
      $composableBuilder(column: $table.config, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BackupDestinationsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BackupDestinationsTableTable,
          BackupDestinationsTableData,
          $$BackupDestinationsTableTableFilterComposer,
          $$BackupDestinationsTableTableOrderingComposer,
          $$BackupDestinationsTableTableAnnotationComposer,
          $$BackupDestinationsTableTableCreateCompanionBuilder,
          $$BackupDestinationsTableTableUpdateCompanionBuilder,
          (
            BackupDestinationsTableData,
            BaseReferences<
              _$AppDatabase,
              $BackupDestinationsTableTable,
              BackupDestinationsTableData
            >,
          ),
          BackupDestinationsTableData,
          PrefetchHooks Function()
        > {
  $$BackupDestinationsTableTableTableManager(
    _$AppDatabase db,
    $BackupDestinationsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BackupDestinationsTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$BackupDestinationsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BackupDestinationsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> config = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BackupDestinationsTableCompanion(
                id: id,
                name: name,
                type: type,
                config: config,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String type,
                required String config,
                Value<bool> enabled = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BackupDestinationsTableCompanion.insert(
                id: id,
                name: name,
                type: type,
                config: config,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BackupDestinationsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BackupDestinationsTableTable,
      BackupDestinationsTableData,
      $$BackupDestinationsTableTableFilterComposer,
      $$BackupDestinationsTableTableOrderingComposer,
      $$BackupDestinationsTableTableAnnotationComposer,
      $$BackupDestinationsTableTableCreateCompanionBuilder,
      $$BackupDestinationsTableTableUpdateCompanionBuilder,
      (
        BackupDestinationsTableData,
        BaseReferences<
          _$AppDatabase,
          $BackupDestinationsTableTable,
          BackupDestinationsTableData
        >,
      ),
      BackupDestinationsTableData,
      PrefetchHooks Function()
    >;
typedef $$SchedulesTableTableCreateCompanionBuilder =
    SchedulesTableCompanion Function({
      required String id,
      required String name,
      required String databaseConfigId,
      required String databaseType,
      required String scheduleType,
      required String scheduleConfig,
      required String destinationIds,
      Value<String> backupFolder,
      Value<String> backupType,
      Value<bool> compressBackup,
      Value<bool> enabled,
      Value<DateTime?> lastRunAt,
      Value<DateTime?> nextRunAt,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SchedulesTableTableUpdateCompanionBuilder =
    SchedulesTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> databaseConfigId,
      Value<String> databaseType,
      Value<String> scheduleType,
      Value<String> scheduleConfig,
      Value<String> destinationIds,
      Value<String> backupFolder,
      Value<String> backupType,
      Value<bool> compressBackup,
      Value<bool> enabled,
      Value<DateTime?> lastRunAt,
      Value<DateTime?> nextRunAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SchedulesTableTableFilterComposer
    extends Composer<_$AppDatabase, $SchedulesTableTable> {
  $$SchedulesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get databaseConfigId => $composableBuilder(
    column: $table.databaseConfigId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get databaseType => $composableBuilder(
    column: $table.databaseType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleType => $composableBuilder(
    column: $table.scheduleType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleConfig => $composableBuilder(
    column: $table.scheduleConfig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationIds => $composableBuilder(
    column: $table.destinationIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backupFolder => $composableBuilder(
    column: $table.backupFolder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backupType => $composableBuilder(
    column: $table.backupType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get compressBackup => $composableBuilder(
    column: $table.compressBackup,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastRunAt => $composableBuilder(
    column: $table.lastRunAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextRunAt => $composableBuilder(
    column: $table.nextRunAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SchedulesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SchedulesTableTable> {
  $$SchedulesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get databaseConfigId => $composableBuilder(
    column: $table.databaseConfigId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get databaseType => $composableBuilder(
    column: $table.databaseType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleType => $composableBuilder(
    column: $table.scheduleType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleConfig => $composableBuilder(
    column: $table.scheduleConfig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationIds => $composableBuilder(
    column: $table.destinationIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backupFolder => $composableBuilder(
    column: $table.backupFolder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backupType => $composableBuilder(
    column: $table.backupType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get compressBackup => $composableBuilder(
    column: $table.compressBackup,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastRunAt => $composableBuilder(
    column: $table.lastRunAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextRunAt => $composableBuilder(
    column: $table.nextRunAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SchedulesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchedulesTableTable> {
  $$SchedulesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get databaseConfigId => $composableBuilder(
    column: $table.databaseConfigId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get databaseType => $composableBuilder(
    column: $table.databaseType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scheduleType => $composableBuilder(
    column: $table.scheduleType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scheduleConfig => $composableBuilder(
    column: $table.scheduleConfig,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationIds => $composableBuilder(
    column: $table.destinationIds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backupFolder => $composableBuilder(
    column: $table.backupFolder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backupType => $composableBuilder(
    column: $table.backupType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get compressBackup => $composableBuilder(
    column: $table.compressBackup,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get lastRunAt =>
      $composableBuilder(column: $table.lastRunAt, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRunAt =>
      $composableBuilder(column: $table.nextRunAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SchedulesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SchedulesTableTable,
          SchedulesTableData,
          $$SchedulesTableTableFilterComposer,
          $$SchedulesTableTableOrderingComposer,
          $$SchedulesTableTableAnnotationComposer,
          $$SchedulesTableTableCreateCompanionBuilder,
          $$SchedulesTableTableUpdateCompanionBuilder,
          (
            SchedulesTableData,
            BaseReferences<
              _$AppDatabase,
              $SchedulesTableTable,
              SchedulesTableData
            >,
          ),
          SchedulesTableData,
          PrefetchHooks Function()
        > {
  $$SchedulesTableTableTableManager(
    _$AppDatabase db,
    $SchedulesTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchedulesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchedulesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchedulesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> databaseConfigId = const Value.absent(),
                Value<String> databaseType = const Value.absent(),
                Value<String> scheduleType = const Value.absent(),
                Value<String> scheduleConfig = const Value.absent(),
                Value<String> destinationIds = const Value.absent(),
                Value<String> backupFolder = const Value.absent(),
                Value<String> backupType = const Value.absent(),
                Value<bool> compressBackup = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime?> lastRunAt = const Value.absent(),
                Value<DateTime?> nextRunAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SchedulesTableCompanion(
                id: id,
                name: name,
                databaseConfigId: databaseConfigId,
                databaseType: databaseType,
                scheduleType: scheduleType,
                scheduleConfig: scheduleConfig,
                destinationIds: destinationIds,
                backupFolder: backupFolder,
                backupType: backupType,
                compressBackup: compressBackup,
                enabled: enabled,
                lastRunAt: lastRunAt,
                nextRunAt: nextRunAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String databaseConfigId,
                required String databaseType,
                required String scheduleType,
                required String scheduleConfig,
                required String destinationIds,
                Value<String> backupFolder = const Value.absent(),
                Value<String> backupType = const Value.absent(),
                Value<bool> compressBackup = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime?> lastRunAt = const Value.absent(),
                Value<DateTime?> nextRunAt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SchedulesTableCompanion.insert(
                id: id,
                name: name,
                databaseConfigId: databaseConfigId,
                databaseType: databaseType,
                scheduleType: scheduleType,
                scheduleConfig: scheduleConfig,
                destinationIds: destinationIds,
                backupFolder: backupFolder,
                backupType: backupType,
                compressBackup: compressBackup,
                enabled: enabled,
                lastRunAt: lastRunAt,
                nextRunAt: nextRunAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SchedulesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SchedulesTableTable,
      SchedulesTableData,
      $$SchedulesTableTableFilterComposer,
      $$SchedulesTableTableOrderingComposer,
      $$SchedulesTableTableAnnotationComposer,
      $$SchedulesTableTableCreateCompanionBuilder,
      $$SchedulesTableTableUpdateCompanionBuilder,
      (
        SchedulesTableData,
        BaseReferences<_$AppDatabase, $SchedulesTableTable, SchedulesTableData>,
      ),
      SchedulesTableData,
      PrefetchHooks Function()
    >;
typedef $$BackupHistoryTableTableCreateCompanionBuilder =
    BackupHistoryTableCompanion Function({
      required String id,
      Value<String?> scheduleId,
      required String databaseName,
      required String databaseType,
      required String backupPath,
      required int fileSize,
      Value<String> backupType,
      required String status,
      Value<String?> errorMessage,
      required DateTime startedAt,
      Value<DateTime?> finishedAt,
      Value<int?> durationSeconds,
      Value<int> rowid,
    });
typedef $$BackupHistoryTableTableUpdateCompanionBuilder =
    BackupHistoryTableCompanion Function({
      Value<String> id,
      Value<String?> scheduleId,
      Value<String> databaseName,
      Value<String> databaseType,
      Value<String> backupPath,
      Value<int> fileSize,
      Value<String> backupType,
      Value<String> status,
      Value<String?> errorMessage,
      Value<DateTime> startedAt,
      Value<DateTime?> finishedAt,
      Value<int?> durationSeconds,
      Value<int> rowid,
    });

class $$BackupHistoryTableTableFilterComposer
    extends Composer<_$AppDatabase, $BackupHistoryTableTable> {
  $$BackupHistoryTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleId => $composableBuilder(
    column: $table.scheduleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get databaseName => $composableBuilder(
    column: $table.databaseName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get databaseType => $composableBuilder(
    column: $table.databaseType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backupPath => $composableBuilder(
    column: $table.backupPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backupType => $composableBuilder(
    column: $table.backupType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BackupHistoryTableTableOrderingComposer
    extends Composer<_$AppDatabase, $BackupHistoryTableTable> {
  $$BackupHistoryTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleId => $composableBuilder(
    column: $table.scheduleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get databaseName => $composableBuilder(
    column: $table.databaseName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get databaseType => $composableBuilder(
    column: $table.databaseType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backupPath => $composableBuilder(
    column: $table.backupPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backupType => $composableBuilder(
    column: $table.backupType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BackupHistoryTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $BackupHistoryTableTable> {
  $$BackupHistoryTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get scheduleId => $composableBuilder(
    column: $table.scheduleId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get databaseName => $composableBuilder(
    column: $table.databaseName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get databaseType => $composableBuilder(
    column: $table.databaseType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backupPath => $composableBuilder(
    column: $table.backupPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get backupType => $composableBuilder(
    column: $table.backupType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );
}

class $$BackupHistoryTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BackupHistoryTableTable,
          BackupHistoryTableData,
          $$BackupHistoryTableTableFilterComposer,
          $$BackupHistoryTableTableOrderingComposer,
          $$BackupHistoryTableTableAnnotationComposer,
          $$BackupHistoryTableTableCreateCompanionBuilder,
          $$BackupHistoryTableTableUpdateCompanionBuilder,
          (
            BackupHistoryTableData,
            BaseReferences<
              _$AppDatabase,
              $BackupHistoryTableTable,
              BackupHistoryTableData
            >,
          ),
          BackupHistoryTableData,
          PrefetchHooks Function()
        > {
  $$BackupHistoryTableTableTableManager(
    _$AppDatabase db,
    $BackupHistoryTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BackupHistoryTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BackupHistoryTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BackupHistoryTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> scheduleId = const Value.absent(),
                Value<String> databaseName = const Value.absent(),
                Value<String> databaseType = const Value.absent(),
                Value<String> backupPath = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String> backupType = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BackupHistoryTableCompanion(
                id: id,
                scheduleId: scheduleId,
                databaseName: databaseName,
                databaseType: databaseType,
                backupPath: backupPath,
                fileSize: fileSize,
                backupType: backupType,
                status: status,
                errorMessage: errorMessage,
                startedAt: startedAt,
                finishedAt: finishedAt,
                durationSeconds: durationSeconds,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> scheduleId = const Value.absent(),
                required String databaseName,
                required String databaseType,
                required String backupPath,
                required int fileSize,
                Value<String> backupType = const Value.absent(),
                required String status,
                Value<String?> errorMessage = const Value.absent(),
                required DateTime startedAt,
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BackupHistoryTableCompanion.insert(
                id: id,
                scheduleId: scheduleId,
                databaseName: databaseName,
                databaseType: databaseType,
                backupPath: backupPath,
                fileSize: fileSize,
                backupType: backupType,
                status: status,
                errorMessage: errorMessage,
                startedAt: startedAt,
                finishedAt: finishedAt,
                durationSeconds: durationSeconds,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BackupHistoryTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BackupHistoryTableTable,
      BackupHistoryTableData,
      $$BackupHistoryTableTableFilterComposer,
      $$BackupHistoryTableTableOrderingComposer,
      $$BackupHistoryTableTableAnnotationComposer,
      $$BackupHistoryTableTableCreateCompanionBuilder,
      $$BackupHistoryTableTableUpdateCompanionBuilder,
      (
        BackupHistoryTableData,
        BaseReferences<
          _$AppDatabase,
          $BackupHistoryTableTable,
          BackupHistoryTableData
        >,
      ),
      BackupHistoryTableData,
      PrefetchHooks Function()
    >;
typedef $$BackupLogsTableTableCreateCompanionBuilder =
    BackupLogsTableCompanion Function({
      required String id,
      Value<String?> backupHistoryId,
      required String level,
      required String category,
      required String message,
      Value<String?> details,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$BackupLogsTableTableUpdateCompanionBuilder =
    BackupLogsTableCompanion Function({
      Value<String> id,
      Value<String?> backupHistoryId,
      Value<String> level,
      Value<String> category,
      Value<String> message,
      Value<String?> details,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$BackupLogsTableTableFilterComposer
    extends Composer<_$AppDatabase, $BackupLogsTableTable> {
  $$BackupLogsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backupHistoryId => $composableBuilder(
    column: $table.backupHistoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get details => $composableBuilder(
    column: $table.details,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BackupLogsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $BackupLogsTableTable> {
  $$BackupLogsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backupHistoryId => $composableBuilder(
    column: $table.backupHistoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get details => $composableBuilder(
    column: $table.details,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BackupLogsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $BackupLogsTableTable> {
  $$BackupLogsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get backupHistoryId => $composableBuilder(
    column: $table.backupHistoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get details =>
      $composableBuilder(column: $table.details, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$BackupLogsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BackupLogsTableTable,
          BackupLogsTableData,
          $$BackupLogsTableTableFilterComposer,
          $$BackupLogsTableTableOrderingComposer,
          $$BackupLogsTableTableAnnotationComposer,
          $$BackupLogsTableTableCreateCompanionBuilder,
          $$BackupLogsTableTableUpdateCompanionBuilder,
          (
            BackupLogsTableData,
            BaseReferences<
              _$AppDatabase,
              $BackupLogsTableTable,
              BackupLogsTableData
            >,
          ),
          BackupLogsTableData,
          PrefetchHooks Function()
        > {
  $$BackupLogsTableTableTableManager(
    _$AppDatabase db,
    $BackupLogsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BackupLogsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BackupLogsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BackupLogsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> backupHistoryId = const Value.absent(),
                Value<String> level = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<String?> details = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BackupLogsTableCompanion(
                id: id,
                backupHistoryId: backupHistoryId,
                level: level,
                category: category,
                message: message,
                details: details,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> backupHistoryId = const Value.absent(),
                required String level,
                required String category,
                required String message,
                Value<String?> details = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => BackupLogsTableCompanion.insert(
                id: id,
                backupHistoryId: backupHistoryId,
                level: level,
                category: category,
                message: message,
                details: details,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BackupLogsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BackupLogsTableTable,
      BackupLogsTableData,
      $$BackupLogsTableTableFilterComposer,
      $$BackupLogsTableTableOrderingComposer,
      $$BackupLogsTableTableAnnotationComposer,
      $$BackupLogsTableTableCreateCompanionBuilder,
      $$BackupLogsTableTableUpdateCompanionBuilder,
      (
        BackupLogsTableData,
        BaseReferences<
          _$AppDatabase,
          $BackupLogsTableTable,
          BackupLogsTableData
        >,
      ),
      BackupLogsTableData,
      PrefetchHooks Function()
    >;
typedef $$EmailConfigsTableTableCreateCompanionBuilder =
    EmailConfigsTableCompanion Function({
      required String id,
      Value<String> senderName,
      Value<String> fromEmail,
      Value<String> fromName,
      Value<String> smtpServer,
      Value<int> smtpPort,
      Value<String> username,
      Value<String> password,
      Value<bool> useSsl,
      Value<String> recipients,
      Value<bool> notifyOnSuccess,
      Value<bool> notifyOnError,
      Value<bool> notifyOnWarning,
      Value<bool> attachLog,
      Value<bool> enabled,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$EmailConfigsTableTableUpdateCompanionBuilder =
    EmailConfigsTableCompanion Function({
      Value<String> id,
      Value<String> senderName,
      Value<String> fromEmail,
      Value<String> fromName,
      Value<String> smtpServer,
      Value<int> smtpPort,
      Value<String> username,
      Value<String> password,
      Value<bool> useSsl,
      Value<String> recipients,
      Value<bool> notifyOnSuccess,
      Value<bool> notifyOnError,
      Value<bool> notifyOnWarning,
      Value<bool> attachLog,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$EmailConfigsTableTableFilterComposer
    extends Composer<_$AppDatabase, $EmailConfigsTableTable> {
  $$EmailConfigsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromEmail => $composableBuilder(
    column: $table.fromEmail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromName => $composableBuilder(
    column: $table.fromName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smtpServer => $composableBuilder(
    column: $table.smtpServer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get smtpPort => $composableBuilder(
    column: $table.smtpPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get useSsl => $composableBuilder(
    column: $table.useSsl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipients => $composableBuilder(
    column: $table.recipients,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get notifyOnSuccess => $composableBuilder(
    column: $table.notifyOnSuccess,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get notifyOnError => $composableBuilder(
    column: $table.notifyOnError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get notifyOnWarning => $composableBuilder(
    column: $table.notifyOnWarning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get attachLog => $composableBuilder(
    column: $table.attachLog,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EmailConfigsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $EmailConfigsTableTable> {
  $$EmailConfigsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromEmail => $composableBuilder(
    column: $table.fromEmail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromName => $composableBuilder(
    column: $table.fromName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smtpServer => $composableBuilder(
    column: $table.smtpServer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get smtpPort => $composableBuilder(
    column: $table.smtpPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get useSsl => $composableBuilder(
    column: $table.useSsl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipients => $composableBuilder(
    column: $table.recipients,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get notifyOnSuccess => $composableBuilder(
    column: $table.notifyOnSuccess,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get notifyOnError => $composableBuilder(
    column: $table.notifyOnError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get notifyOnWarning => $composableBuilder(
    column: $table.notifyOnWarning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get attachLog => $composableBuilder(
    column: $table.attachLog,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EmailConfigsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmailConfigsTableTable> {
  $$EmailConfigsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get senderName => $composableBuilder(
    column: $table.senderName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fromEmail =>
      $composableBuilder(column: $table.fromEmail, builder: (column) => column);

  GeneratedColumn<String> get fromName =>
      $composableBuilder(column: $table.fromName, builder: (column) => column);

  GeneratedColumn<String> get smtpServer => $composableBuilder(
    column: $table.smtpServer,
    builder: (column) => column,
  );

  GeneratedColumn<int> get smtpPort =>
      $composableBuilder(column: $table.smtpPort, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get password =>
      $composableBuilder(column: $table.password, builder: (column) => column);

  GeneratedColumn<bool> get useSsl =>
      $composableBuilder(column: $table.useSsl, builder: (column) => column);

  GeneratedColumn<String> get recipients => $composableBuilder(
    column: $table.recipients,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get notifyOnSuccess => $composableBuilder(
    column: $table.notifyOnSuccess,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get notifyOnError => $composableBuilder(
    column: $table.notifyOnError,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get notifyOnWarning => $composableBuilder(
    column: $table.notifyOnWarning,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get attachLog =>
      $composableBuilder(column: $table.attachLog, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$EmailConfigsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EmailConfigsTableTable,
          EmailConfigsTableData,
          $$EmailConfigsTableTableFilterComposer,
          $$EmailConfigsTableTableOrderingComposer,
          $$EmailConfigsTableTableAnnotationComposer,
          $$EmailConfigsTableTableCreateCompanionBuilder,
          $$EmailConfigsTableTableUpdateCompanionBuilder,
          (
            EmailConfigsTableData,
            BaseReferences<
              _$AppDatabase,
              $EmailConfigsTableTable,
              EmailConfigsTableData
            >,
          ),
          EmailConfigsTableData,
          PrefetchHooks Function()
        > {
  $$EmailConfigsTableTableTableManager(
    _$AppDatabase db,
    $EmailConfigsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmailConfigsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmailConfigsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmailConfigsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> senderName = const Value.absent(),
                Value<String> fromEmail = const Value.absent(),
                Value<String> fromName = const Value.absent(),
                Value<String> smtpServer = const Value.absent(),
                Value<int> smtpPort = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> password = const Value.absent(),
                Value<bool> useSsl = const Value.absent(),
                Value<String> recipients = const Value.absent(),
                Value<bool> notifyOnSuccess = const Value.absent(),
                Value<bool> notifyOnError = const Value.absent(),
                Value<bool> notifyOnWarning = const Value.absent(),
                Value<bool> attachLog = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EmailConfigsTableCompanion(
                id: id,
                senderName: senderName,
                fromEmail: fromEmail,
                fromName: fromName,
                smtpServer: smtpServer,
                smtpPort: smtpPort,
                username: username,
                password: password,
                useSsl: useSsl,
                recipients: recipients,
                notifyOnSuccess: notifyOnSuccess,
                notifyOnError: notifyOnError,
                notifyOnWarning: notifyOnWarning,
                attachLog: attachLog,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> senderName = const Value.absent(),
                Value<String> fromEmail = const Value.absent(),
                Value<String> fromName = const Value.absent(),
                Value<String> smtpServer = const Value.absent(),
                Value<int> smtpPort = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> password = const Value.absent(),
                Value<bool> useSsl = const Value.absent(),
                Value<String> recipients = const Value.absent(),
                Value<bool> notifyOnSuccess = const Value.absent(),
                Value<bool> notifyOnError = const Value.absent(),
                Value<bool> notifyOnWarning = const Value.absent(),
                Value<bool> attachLog = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => EmailConfigsTableCompanion.insert(
                id: id,
                senderName: senderName,
                fromEmail: fromEmail,
                fromName: fromName,
                smtpServer: smtpServer,
                smtpPort: smtpPort,
                username: username,
                password: password,
                useSsl: useSsl,
                recipients: recipients,
                notifyOnSuccess: notifyOnSuccess,
                notifyOnError: notifyOnError,
                notifyOnWarning: notifyOnWarning,
                attachLog: attachLog,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EmailConfigsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EmailConfigsTableTable,
      EmailConfigsTableData,
      $$EmailConfigsTableTableFilterComposer,
      $$EmailConfigsTableTableOrderingComposer,
      $$EmailConfigsTableTableAnnotationComposer,
      $$EmailConfigsTableTableCreateCompanionBuilder,
      $$EmailConfigsTableTableUpdateCompanionBuilder,
      (
        EmailConfigsTableData,
        BaseReferences<
          _$AppDatabase,
          $EmailConfigsTableTable,
          EmailConfigsTableData
        >,
      ),
      EmailConfigsTableData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SqlServerConfigsTableTableTableManager get sqlServerConfigsTable =>
      $$SqlServerConfigsTableTableTableManager(_db, _db.sqlServerConfigsTable);
  $$SybaseConfigsTableTableTableManager get sybaseConfigsTable =>
      $$SybaseConfigsTableTableTableManager(_db, _db.sybaseConfigsTable);
  $$BackupDestinationsTableTableTableManager get backupDestinationsTable =>
      $$BackupDestinationsTableTableTableManager(
        _db,
        _db.backupDestinationsTable,
      );
  $$SchedulesTableTableTableManager get schedulesTable =>
      $$SchedulesTableTableTableManager(_db, _db.schedulesTable);
  $$BackupHistoryTableTableTableManager get backupHistoryTable =>
      $$BackupHistoryTableTableTableManager(_db, _db.backupHistoryTable);
  $$BackupLogsTableTableTableManager get backupLogsTable =>
      $$BackupLogsTableTableTableManager(_db, _db.backupLogsTable);
  $$EmailConfigsTableTableTableManager get emailConfigsTable =>
      $$EmailConfigsTableTableTableManager(_db, _db.emailConfigsTable);
}
