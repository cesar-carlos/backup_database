import 'package:uuid/uuid.dart';

enum DestinationType { local, ftp, googleDrive }

class BackupDestination {
  final String id;
  final String name;
  final DestinationType type;
  final String config; // JSON com configurações específicas do tipo
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  BackupDestination({
    String? id,
    required this.name,
    required this.type,
    required this.config,
    this.enabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  BackupDestination copyWith({
    String? id,
    String? name,
    DestinationType? type,
    String? config,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BackupDestination(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      config: config ?? this.config,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupDestination &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// Configurações específicas para cada tipo de destino
class LocalDestinationConfig {
  final String path;
  final bool createSubfoldersByDate;
  final int retentionDays;

  const LocalDestinationConfig({
    required this.path,
    this.createSubfoldersByDate = true,
    this.retentionDays = 30,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'createSubfoldersByDate': createSubfoldersByDate,
        'retentionDays': retentionDays,
      };

  factory LocalDestinationConfig.fromJson(Map<String, dynamic> json) {
    return LocalDestinationConfig(
      path: json['path'] as String,
      createSubfoldersByDate: json['createSubfoldersByDate'] as bool? ?? true,
      retentionDays: json['retentionDays'] as int? ?? 30,
    );
  }
}

class FtpDestinationConfig {
  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;
  final bool useFtps;
  final int retentionDays;

  const FtpDestinationConfig({
    required this.host,
    this.port = 21,
    required this.username,
    required this.password,
    required this.remotePath,
    this.useFtps = false,
    this.retentionDays = 30,
  });

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'remotePath': remotePath,
        'useFtps': useFtps,
        'retentionDays': retentionDays,
      };

  factory FtpDestinationConfig.fromJson(Map<String, dynamic> json) {
    return FtpDestinationConfig(
      host: json['host'] as String,
      port: json['port'] as int? ?? 21,
      username: json['username'] as String,
      password: json['password'] as String,
      remotePath: json['remotePath'] as String,
      useFtps: json['useFtps'] as bool? ?? false,
      retentionDays: json['retentionDays'] as int? ?? 30,
    );
  }
}

class GoogleDriveDestinationConfig {
  final String folderId;
  final String folderName;
  final String accessToken;
  final String refreshToken;
  final int retentionDays;

  const GoogleDriveDestinationConfig({
    required this.folderId,
    required this.folderName,
    required this.accessToken,
    required this.refreshToken,
    this.retentionDays = 30,
  });

  Map<String, dynamic> toJson() => {
        'folderId': folderId,
        'folderName': folderName,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'retentionDays': retentionDays,
      };

  factory GoogleDriveDestinationConfig.fromJson(Map<String, dynamic> json) {
    return GoogleDriveDestinationConfig(
      folderId: json['folderId'] as String,
      folderName: json['folderName'] as String,
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      retentionDays: json['retentionDays'] as int? ?? 30,
    );
  }
}

