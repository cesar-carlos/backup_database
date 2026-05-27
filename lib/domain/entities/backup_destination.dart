import 'package:backup_database/core/constants/destination_retry_constants.dart'
    show DestinationRetryConstants, StepTimeoutConstants;
import 'package:uuid/uuid.dart';

enum DestinationType { local, ftp, googleDrive, dropbox, nextcloud }

class BackupDestination {
  BackupDestination({
    required this.name,
    required this.type,
    required this.config,
    String? id,
    this.enabled = true,
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
  final DateTime createdAt;
  final DateTime updatedAt;

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

class LocalDestinationConfig {
  const LocalDestinationConfig({
    required this.path,
    this.createSubfoldersByDate = true,
    this.retentionDays = 30,
    this.protectedBackupIdShortPrefixes = const {},
    this.enableHashValidation = true,
  });

  factory LocalDestinationConfig.fromJson(Map<String, dynamic> json) {
    return LocalDestinationConfig(
      path: json['path'] as String,
      createSubfoldersByDate: json['createSubfoldersByDate'] as bool? ?? true,
      retentionDays: json['retentionDays'] as int? ?? 30,
      enableHashValidation: json['enableHashValidation'] as bool? ?? true,
    );
  }
  final String path;
  final bool createSubfoldersByDate;
  final int retentionDays;
  final Set<String> protectedBackupIdShortPrefixes;

  /// Quando `true` (default), valida o backup copiado computando SHA-256
  /// do source e do destination e comparando. Garante integridade total
  /// mas custa 1× I/O extra (leitura do destination). Para backups muito
  /// grandes em destinos confiáveis (mesmo volume, sem rede), pode ser
  /// desabilitado para ganhar performance — a checagem de tamanho ainda
  /// pega 99% dos casos de cópia parcial.
  final bool enableHashValidation;

  Map<String, dynamic> toJson() => {
    'path': path,
    'createSubfoldersByDate': createSubfoldersByDate,
    'retentionDays': retentionDays,
    'enableHashValidation': enableHashValidation,
  };
}

enum FtpWhenResumeNotSupported { fallback, fail }

class FtpDestinationConfig {
  const FtpDestinationConfig({
    required this.host,
    required this.username,
    required this.password,
    required this.remotePath,
    this.port = 21,
    this.useFtps = false,
    this.retentionDays = 30,
    this.enableResume = true,
    this.keepPartOnCancel = true,
    this.maxAttempts,
    this.whenResumeNotSupported = FtpWhenResumeNotSupported.fallback,
    this.enableVerboseLog = false,
    this.connectionTimeoutSeconds,
    this.uploadTimeoutMinutes,
    this.enableStrongIntegrityValidation = false,
    this.enableReadBackValidation = false,
    this.allowInvalidCertificates = true,
    this.protectedBackupIdShortPrefixes = const {},
  });

  factory FtpDestinationConfig.fromJson(Map<String, dynamic> json) {
    final whenStr = json['whenResumeNotSupported'] as String?;
    final whenResume = whenStr != null
        ? FtpWhenResumeNotSupported.values.firstWhere(
            (e) => e.name == whenStr,
            orElse: () => FtpWhenResumeNotSupported.fallback,
          )
        : FtpWhenResumeNotSupported.fallback;

    return FtpDestinationConfig(
      host: json['host'] as String,
      port: json['port'] as int? ?? 21,
      username: json['username'] as String,
      password: json['password'] as String,
      remotePath: json['remotePath'] as String? ?? '/',
      useFtps: json['useFtps'] as bool? ?? false,
      retentionDays: json['retentionDays'] as int? ?? 30,
      enableResume: json['enableResume'] as bool? ?? true,
      keepPartOnCancel: json['keepPartOnCancel'] as bool? ?? true,
      maxAttempts: json['maxAttempts'] as int?,
      whenResumeNotSupported: whenResume,
      enableVerboseLog: json['enableVerboseLog'] as bool? ?? false,
      connectionTimeoutSeconds: json['connectionTimeoutSeconds'] as int?,
      uploadTimeoutMinutes: json['uploadTimeoutMinutes'] as int?,
      enableStrongIntegrityValidation:
          json['enableStrongIntegrityValidation'] as bool? ?? false,
      enableReadBackValidation:
          json['enableReadBackValidation'] as bool? ?? false,
      allowInvalidCertificates:
          json['allowInvalidCertificates'] as bool? ?? true,
    );
  }

  FtpDestinationConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? remotePath,
    bool? useFtps,
    int? retentionDays,
    bool? enableResume,
    bool? keepPartOnCancel,
    int? maxAttempts,
    FtpWhenResumeNotSupported? whenResumeNotSupported,
    bool? enableVerboseLog,
    int? connectionTimeoutSeconds,
    int? uploadTimeoutMinutes,
    bool? enableStrongIntegrityValidation,
    bool? enableReadBackValidation,
    bool? allowInvalidCertificates,
    Set<String>? protectedBackupIdShortPrefixes,
  }) {
    return FtpDestinationConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
      useFtps: useFtps ?? this.useFtps,
      retentionDays: retentionDays ?? this.retentionDays,
      enableResume: enableResume ?? this.enableResume,
      keepPartOnCancel: keepPartOnCancel ?? this.keepPartOnCancel,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      whenResumeNotSupported:
          whenResumeNotSupported ?? this.whenResumeNotSupported,
      enableVerboseLog: enableVerboseLog ?? this.enableVerboseLog,
      connectionTimeoutSeconds:
          connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
      uploadTimeoutMinutes: uploadTimeoutMinutes ?? this.uploadTimeoutMinutes,
      enableStrongIntegrityValidation:
          enableStrongIntegrityValidation ??
          this.enableStrongIntegrityValidation,
      enableReadBackValidation:
          enableReadBackValidation ?? this.enableReadBackValidation,
      allowInvalidCertificates:
          allowInvalidCertificates ?? this.allowInvalidCertificates,
      protectedBackupIdShortPrefixes:
          protectedBackupIdShortPrefixes ?? this.protectedBackupIdShortPrefixes,
    );
  }

  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;
  final bool useFtps;
  final int retentionDays;
  final bool enableResume;
  final bool keepPartOnCancel;
  final int? maxAttempts;
  final FtpWhenResumeNotSupported whenResumeNotSupported;
  final bool enableVerboseLog;
  final int? connectionTimeoutSeconds;
  final int? uploadTimeoutMinutes;
  final bool enableStrongIntegrityValidation;
  final bool enableReadBackValidation;
  final bool allowInvalidCertificates;
  final Set<String> protectedBackupIdShortPrefixes;

  int get effectiveMaxAttempts =>
      maxAttempts ?? DestinationRetryConstants.maxAttempts;

  int get effectiveConnectionTimeoutSeconds =>
      connectionTimeoutSeconds ?? StepTimeoutConstants.ftpConnection.inSeconds;

  int get effectiveUploadTimeoutSeconds =>
      (uploadTimeoutMinutes ?? StepTimeoutConstants.uploadFtp.inMinutes) * 60;

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'remotePath': remotePath,
    'useFtps': useFtps,
    'retentionDays': retentionDays,
    'enableResume': enableResume,
    'keepPartOnCancel': keepPartOnCancel,
    if (maxAttempts != null) 'maxAttempts': maxAttempts,
    'whenResumeNotSupported': whenResumeNotSupported.name,
    'enableVerboseLog': enableVerboseLog,
    'enableStrongIntegrityValidation': enableStrongIntegrityValidation,
    'enableReadBackValidation': enableReadBackValidation,
    'allowInvalidCertificates': allowInvalidCertificates,
    if (connectionTimeoutSeconds != null)
      'connectionTimeoutSeconds': connectionTimeoutSeconds,
    if (uploadTimeoutMinutes != null)
      'uploadTimeoutMinutes': uploadTimeoutMinutes,
  };
}

class GoogleDriveDestinationConfig {
  const GoogleDriveDestinationConfig({
    required this.folderId,
    required this.folderName,
    required this.accessToken,
    required this.refreshToken,
    this.retentionDays = 30,
    this.protectedBackupIdShortPrefixes = const {},
  });

  factory GoogleDriveDestinationConfig.fromJson(Map<String, dynamic> json) {
    return GoogleDriveDestinationConfig(
      folderId: json['folderId'] as String,
      folderName: json['folderName'] as String? ?? 'Backups',
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      retentionDays: json['retentionDays'] as int? ?? 30,
    );
  }

  GoogleDriveDestinationConfig copyWith({
    String? folderId,
    String? folderName,
    String? accessToken,
    String? refreshToken,
    int? retentionDays,
    Set<String>? protectedBackupIdShortPrefixes,
  }) {
    return GoogleDriveDestinationConfig(
      folderId: folderId ?? this.folderId,
      folderName: folderName ?? this.folderName,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      retentionDays: retentionDays ?? this.retentionDays,
      protectedBackupIdShortPrefixes:
          protectedBackupIdShortPrefixes ?? this.protectedBackupIdShortPrefixes,
    );
  }

  final String folderId;
  final String folderName;
  final String accessToken;
  final String refreshToken;
  final int retentionDays;
  final Set<String> protectedBackupIdShortPrefixes;

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
    this.protectedBackupIdShortPrefixes = const {},
  });

  factory DropboxDestinationConfig.fromJson(Map<String, dynamic> json) {
    return DropboxDestinationConfig(
      folderPath: json['folderPath'] as String? ?? '',
      folderName: json['folderName'] as String? ?? 'Backups',
      retentionDays: json['retentionDays'] as int? ?? 30,
    );
  }

  DropboxDestinationConfig copyWith({
    String? folderPath,
    String? folderName,
    int? retentionDays,
    Set<String>? protectedBackupIdShortPrefixes,
  }) {
    return DropboxDestinationConfig(
      folderPath: folderPath ?? this.folderPath,
      folderName: folderName ?? this.folderName,
      retentionDays: retentionDays ?? this.retentionDays,
      protectedBackupIdShortPrefixes:
          protectedBackupIdShortPrefixes ?? this.protectedBackupIdShortPrefixes,
    );
  }

  final String folderPath;
  final String folderName;
  final int retentionDays;
  final Set<String> protectedBackupIdShortPrefixes;

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
    this.enableStrongIntegrityValidation = false,
    this.enableReadBackValidation = false,
    this.protectedBackupIdShortPrefixes = const {},
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
      enableStrongIntegrityValidation:
          json['enableStrongIntegrityValidation'] as bool? ?? false,
      enableReadBackValidation:
          json['enableReadBackValidation'] as bool? ?? false,
    );
  }

  NextcloudDestinationConfig copyWith({
    String? serverUrl,
    String? username,
    String? appPassword,
    NextcloudAuthMode? authMode,
    String? remotePath,
    String? folderName,
    bool? allowInvalidCertificates,
    int? retentionDays,
    bool? enableStrongIntegrityValidation,
    bool? enableReadBackValidation,
    Set<String>? protectedBackupIdShortPrefixes,
  }) {
    return NextcloudDestinationConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      appPassword: appPassword ?? this.appPassword,
      authMode: authMode ?? this.authMode,
      remotePath: remotePath ?? this.remotePath,
      folderName: folderName ?? this.folderName,
      allowInvalidCertificates:
          allowInvalidCertificates ?? this.allowInvalidCertificates,
      retentionDays: retentionDays ?? this.retentionDays,
      enableStrongIntegrityValidation:
          enableStrongIntegrityValidation ??
          this.enableStrongIntegrityValidation,
      enableReadBackValidation:
          enableReadBackValidation ?? this.enableReadBackValidation,
      protectedBackupIdShortPrefixes:
          protectedBackupIdShortPrefixes ?? this.protectedBackupIdShortPrefixes,
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
  final bool enableStrongIntegrityValidation;
  final bool enableReadBackValidation;
  final Set<String> protectedBackupIdShortPrefixes;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'appPassword': appPassword,
    'authMode': authMode.name,
    'remotePath': remotePath,
    'folderName': folderName,
    'allowInvalidCertificates': allowInvalidCertificates,
    'retentionDays': retentionDays,
    'enableStrongIntegrityValidation': enableStrongIntegrityValidation,
    'enableReadBackValidation': enableReadBackValidation,
  };
}
