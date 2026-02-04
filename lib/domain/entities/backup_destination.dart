import 'package:uuid/uuid.dart';

enum DestinationType { local, ftp, googleDrive, dropbox, nextcloud }

class BackupDestination {
  BackupDestination({
    required this.name,
    required this.type,
    required this.config,
    String? id,
    this.enabled = true,
    this.tempPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
  final String id;
  final String name;
  final DestinationType type;
  final String config;
  final bool enabled;
  final String? tempPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  BackupDestination copyWith({
    String? id,
    String? name,
    DestinationType? type,
    String? config,
    bool? enabled,
    String? tempPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BackupDestination(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      config: config ?? this.config,
      enabled: enabled ?? this.enabled,
      tempPath: tempPath ?? this.tempPath,
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

class LocalDestinationConfig {
  const LocalDestinationConfig({
    required this.path,
    this.createSubfoldersByDate = true,
    this.retentionDays = 30,
  });

  factory LocalDestinationConfig.fromJson(Map<String, dynamic> json) {
    return LocalDestinationConfig(
      path: json['path'] as String,
      createSubfoldersByDate: json['createSubfoldersByDate'] as bool? ?? true,
      retentionDays: json['retentionDays'] as int? ?? 30,
    );
  }
  final String path;
  final bool createSubfoldersByDate;
  final int retentionDays;

  Map<String, dynamic> toJson() => {
    'path': path,
    'createSubfoldersByDate': createSubfoldersByDate,
    'retentionDays': retentionDays,
  };
}

class FtpDestinationConfig {
  const FtpDestinationConfig({
    required this.host,
    required this.username,
    required this.password,
    required this.remotePath,
    this.port = 21,
    this.useFtps = false,
    this.retentionDays = 30,
  });

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
  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;
  final bool useFtps;
  final int retentionDays;

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'remotePath': remotePath,
    'useFtps': useFtps,
    'retentionDays': retentionDays,
  };
}

class GoogleDriveDestinationConfig {
  const GoogleDriveDestinationConfig({
    required this.folderId,
    required this.folderName,
    required this.accessToken,
    required this.refreshToken,
    this.retentionDays = 30,
  });

  factory GoogleDriveDestinationConfig.fromJson(Map<String, dynamic> json) {
    return GoogleDriveDestinationConfig(
      folderId: json['folderId'] as String,
      folderName: json['folderName'] as String,
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      retentionDays: json['retentionDays'] as int? ?? 30,
    );
  }
  final String folderId;
  final String folderName;
  final String accessToken;
  final String refreshToken;
  final int retentionDays;

  Map<String, dynamic> toJson() => {
    'folderId': folderId,
    'folderName': folderName,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'retentionDays': retentionDays,
  };
}

class DropboxDestinationConfig {
  const DropboxDestinationConfig({
    required this.folderPath,
    this.folderName = 'Backups',
    this.retentionDays = 30,
  });

  factory DropboxDestinationConfig.fromJson(Map<String, dynamic> json) {
    return DropboxDestinationConfig(
      folderPath: json['folderPath'] as String,
      folderName: json['folderName'] as String? ?? 'Backups',
      retentionDays: json['retentionDays'] as int? ?? 30,
    );
  }
  final String folderPath;
  final String folderName;
  final int retentionDays;

  Map<String, dynamic> toJson() => {
    'folderPath': folderPath,
    'folderName': folderName,
    'retentionDays': retentionDays,
  };
}

enum NextcloudAuthMode { appPassword, userPassword }

class NextcloudDestinationConfig {
  const NextcloudDestinationConfig({
    required this.serverUrl,
    required this.username,
    required this.appPassword,
    this.authMode = NextcloudAuthMode.appPassword,
    this.remotePath = '/',
    this.folderName = 'Backups',
    this.allowInvalidCertificates = false,
    this.retentionDays = 30,
  });

  factory NextcloudDestinationConfig.fromJson(Map<String, dynamic> json) {
    final authModeStr = json['authMode'] as String?;
    final authMode = NextcloudAuthMode.values.firstWhere(
      (e) => e.name == authModeStr,
      orElse: () => NextcloudAuthMode.appPassword,
    );

    return NextcloudDestinationConfig(
      serverUrl: json['serverUrl'] as String,
      username: json['username'] as String,
      appPassword: json['appPassword'] as String,
      authMode: authMode,
      remotePath: json['remotePath'] as String? ?? '/',
      folderName: json['folderName'] as String? ?? 'Backups',
      allowInvalidCertificates:
          json['allowInvalidCertificates'] as bool? ?? false,
      retentionDays: json['retentionDays'] as int? ?? 30,
    );
  }
  final String serverUrl;
  final String username;
  final String appPassword;
  final NextcloudAuthMode authMode;
  final String remotePath;
  final String folderName;
  final bool allowInvalidCertificates;
  final int retentionDays;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'appPassword': appPassword,
    'authMode': authMode.name,
    'remotePath': remotePath,
    'folderName': folderName,
    'allowInvalidCertificates': allowInvalidCertificates,
    'retentionDays': retentionDays,
  };
}
