import 'package:uuid/uuid.dart';

class SybaseConfig {
  final String id;
  final String name;
  final String serverName; // Nome da máquina/servidor
  final String databaseName; // Nome do banco de dados (DBN)
  final String databaseFile;
  final int port;
  final String username;
  final String password;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  SybaseConfig({
    String? id,
    required this.name,
    required this.serverName,
    required this.databaseName,
    this.databaseFile = '', // Opcional - não necessário para backup quando usando ENG+DBN
    this.port = 2638,
    required this.username,
    required this.password,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  SybaseConfig copyWith({
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

