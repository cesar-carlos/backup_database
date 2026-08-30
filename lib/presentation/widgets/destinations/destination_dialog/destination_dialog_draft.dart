import 'dart:convert';

import 'package:backup_database/domain/entities/backup_destination.dart';

class DestinationDialogDraft {
  const DestinationDialogDraft({
    required this.name,
    required this.type,
    required this.enabled,
    required this.retentionDays,
    this.id,
    this.createdAt,
    this.localPath = '',
    this.createSubfoldersByDate = true,
    this.ftpHost = '',
    this.ftpPortText = '21',
    this.ftpUsername = '',
    this.ftpPassword = '',
    this.ftpRemotePath = '/backups',
    this.useFtps = false,
    this.ftpAllowInvalidCertificates = true,
    this.enableResumeFtp = true,
    this.keepPartOnCancelFtp = true,
    this.whenResumeNotSupportedFtp = FtpWhenResumeNotSupported.fallback,
    this.ftpMaxAttemptsText = '',
    this.enableVerboseLogFtp = false,
    this.enableStrongIntegrityValidationFtp = false,
    this.enableReadBackValidationFtp = false,
    this.ftpConnectionTimeoutSecondsText = '',
    this.ftpUploadTimeoutMinutesText = '',
    this.googleFolderName = 'Backups',
    this.dropboxFolderPath = '',
    this.dropboxFolderName = 'Backups',
    this.nextcloudServerUrl = '',
    this.nextcloudUsername = '',
    this.nextcloudAppPassword = '',
    this.nextcloudAuthMode = NextcloudAuthMode.appPassword,
    this.nextcloudRemotePath = '/',
    this.nextcloudFolderName = 'Backups',
    this.nextcloudAllowInvalidCertificates = false,
  });

  final String? id;
  final String name;
  final DestinationType type;
  final bool enabled;
  final DateTime? createdAt;
  final int retentionDays;

  final String localPath;
  final bool createSubfoldersByDate;

  final String ftpHost;
  final String ftpPortText;
  final String ftpUsername;
  final String ftpPassword;
  final String ftpRemotePath;
  final bool useFtps;
  final bool ftpAllowInvalidCertificates;
  final bool enableResumeFtp;
  final bool keepPartOnCancelFtp;
  final FtpWhenResumeNotSupported whenResumeNotSupportedFtp;
  final String ftpMaxAttemptsText;
  final bool enableVerboseLogFtp;
  final bool enableStrongIntegrityValidationFtp;
  final bool enableReadBackValidationFtp;
  final String ftpConnectionTimeoutSecondsText;
  final String ftpUploadTimeoutMinutesText;

  final String googleFolderName;

  final String dropboxFolderPath;
  final String dropboxFolderName;

  final String nextcloudServerUrl;
  final String nextcloudUsername;
  final String nextcloudAppPassword;
  final NextcloudAuthMode nextcloudAuthMode;
  final String nextcloudRemotePath;
  final String nextcloudFolderName;
  final bool nextcloudAllowInvalidCertificates;

  BackupDestination toDestination() {
    return BackupDestination(
      id: id,
      name: name,
      type: type,
      config: configJson,
      enabled: enabled,
      createdAt: createdAt,
    );
  }

  String get configJson {
    return switch (type) {
      DestinationType.local => localConfigJson(),
      DestinationType.ftp => ftpConfigJson(),
      DestinationType.googleDrive => googleDriveConfigJson(),
      DestinationType.dropbox => dropboxConfigJson(),
      DestinationType.nextcloud => nextcloudConfigJson(),
    };
  }

  String localConfigJson() {
    return jsonEncode({
      'path': localPath,
      'createSubfoldersByDate': createSubfoldersByDate,
      'retentionDays': retentionDays,
    });
  }

  String ftpConfigJson() {
    final maxAttempts = _optionalInt(ftpMaxAttemptsText);
    final connTimeout = _optionalInt(ftpConnectionTimeoutSecondsText);
    final uploadTimeout = _optionalInt(ftpUploadTimeoutMinutesText);
    return jsonEncode({
      'host': ftpHost,
      'port': int.parse(ftpPortText),
      'username': ftpUsername,
      'password': ftpPassword,
      'remotePath': ftpRemotePath,
      'useFtps': useFtps,
      'allowInvalidCertificates': ftpAllowInvalidCertificates,
      'enableResume': enableResumeFtp,
      'keepPartOnCancel': keepPartOnCancelFtp,
      'whenResumeNotSupported': whenResumeNotSupportedFtp.name,
      ...?(maxAttempts != null ? {'maxAttempts': maxAttempts} : null),
      'enableVerboseLog': enableVerboseLogFtp,
      'enableStrongIntegrityValidation': enableStrongIntegrityValidationFtp,
      'enableReadBackValidation': enableReadBackValidationFtp,
      ...?(connTimeout != null
          ? {'connectionTimeoutSeconds': connTimeout}
          : null),
      ...?(uploadTimeout != null
          ? {'uploadTimeoutMinutes': uploadTimeout}
          : null),
      'retentionDays': retentionDays,
    });
  }

  String googleDriveConfigJson() {
    return jsonEncode({
      'folderName': googleFolderName,
      'folderId': 'root',
      'retentionDays': retentionDays,
    });
  }

  String dropboxConfigJson() {
    return jsonEncode({
      'folderPath': dropboxFolderPath,
      'folderName': dropboxFolderName,
      'retentionDays': retentionDays,
    });
  }

  String nextcloudConfigJson() {
    return jsonEncode({
      'serverUrl': nextcloudServerUrl,
      'username': nextcloudUsername,
      'appPassword': nextcloudAppPassword,
      'authMode': nextcloudAuthMode.name,
      'remotePath': nextcloudRemotePath,
      'folderName': nextcloudFolderName,
      'allowInvalidCertificates': nextcloudAllowInvalidCertificates,
      'retentionDays': retentionDays,
    });
  }

  static int? _optionalInt(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : int.tryParse(trimmed);
  }
}
