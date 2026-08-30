import 'dart:convert';

import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog/destination_dialog_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 30, 12);

  DestinationDialogDraft draft({
    required DestinationType type,
    String? id = 'dest-1',
    String name = 'Nightly',
    bool enabled = true,
    int retentionDays = 7,
    String localPath = r'C:\Backups',
    bool createSubfoldersByDate = true,
    String ftpHost = 'ftp.example.com',
    String ftpPortText = '21',
    String ftpUsername = 'user',
    String ftpPassword = 'secret',
    String ftpRemotePath = '/backups',
    bool useFtps = false,
    bool ftpAllowInvalidCertificates = true,
    bool enableResumeFtp = true,
    bool keepPartOnCancelFtp = true,
    FtpWhenResumeNotSupported whenResumeNotSupportedFtp =
        FtpWhenResumeNotSupported.fallback,
    String ftpMaxAttemptsText = '',
    bool enableVerboseLogFtp = false,
    bool enableStrongIntegrityValidationFtp = false,
    bool enableReadBackValidationFtp = false,
    String ftpConnectionTimeoutSecondsText = '',
    String ftpUploadTimeoutMinutesText = '',
    String googleFolderName = 'Backups',
    String dropboxFolderPath = '/Apps',
    String dropboxFolderName = 'Backups',
    String nextcloudServerUrl = 'https://cloud.example.com',
    String nextcloudUsername = 'nc-user',
    String nextcloudAppPassword = 'enc:app-pass',
    NextcloudAuthMode nextcloudAuthMode = NextcloudAuthMode.appPassword,
    String nextcloudRemotePath = '/',
    String nextcloudFolderName = 'Backups',
    bool nextcloudAllowInvalidCertificates = false,
  }) {
    return DestinationDialogDraft(
      id: id,
      name: name,
      type: type,
      enabled: enabled,
      createdAt: createdAt,
      retentionDays: retentionDays,
      localPath: localPath,
      createSubfoldersByDate: createSubfoldersByDate,
      ftpHost: ftpHost,
      ftpPortText: ftpPortText,
      ftpUsername: ftpUsername,
      ftpPassword: ftpPassword,
      ftpRemotePath: ftpRemotePath,
      useFtps: useFtps,
      ftpAllowInvalidCertificates: ftpAllowInvalidCertificates,
      enableResumeFtp: enableResumeFtp,
      keepPartOnCancelFtp: keepPartOnCancelFtp,
      whenResumeNotSupportedFtp: whenResumeNotSupportedFtp,
      ftpMaxAttemptsText: ftpMaxAttemptsText,
      enableVerboseLogFtp: enableVerboseLogFtp,
      enableStrongIntegrityValidationFtp: enableStrongIntegrityValidationFtp,
      enableReadBackValidationFtp: enableReadBackValidationFtp,
      ftpConnectionTimeoutSecondsText: ftpConnectionTimeoutSecondsText,
      ftpUploadTimeoutMinutesText: ftpUploadTimeoutMinutesText,
      googleFolderName: googleFolderName,
      dropboxFolderPath: dropboxFolderPath,
      dropboxFolderName: dropboxFolderName,
      nextcloudServerUrl: nextcloudServerUrl,
      nextcloudUsername: nextcloudUsername,
      nextcloudAppPassword: nextcloudAppPassword,
      nextcloudAuthMode: nextcloudAuthMode,
      nextcloudRemotePath: nextcloudRemotePath,
      nextcloudFolderName: nextcloudFolderName,
      nextcloudAllowInvalidCertificates: nextcloudAllowInvalidCertificates,
    );
  }

  Map<String, dynamic> configOf(DestinationDialogDraft value) {
    return jsonDecode(value.toDestination().config) as Map<String, dynamic>;
  }

  group('DestinationDialogDraft.toDestination', () {
    test('local maps path, subfolders and identity', () {
      final destination = draft(
        type: DestinationType.local,
        createSubfoldersByDate: false,
        enabled: false,
      ).toDestination();

      expect(destination.id, 'dest-1');
      expect(destination.name, 'Nightly');
      expect(destination.type, DestinationType.local);
      expect(destination.enabled, isFalse);
      expect(destination.createdAt, createdAt);
      expect(jsonDecode(destination.config), {
        'path': r'C:\Backups',
        'createSubfoldersByDate': false,
        'retentionDays': 7,
      });
    });

    test('FTP omits empty optional timeout and attempt keys', () {
      final config = configOf(
        draft(type: DestinationType.ftp),
      );

      expect(config['host'], 'ftp.example.com');
      expect(config['port'], 21);
      expect(config['username'], 'user');
      expect(config['password'], 'secret');
      expect(config['remotePath'], '/backups');
      expect(config['useFtps'], isFalse);
      expect(config['allowInvalidCertificates'], isTrue);
      expect(config['enableResume'], isTrue);
      expect(config['keepPartOnCancel'], isTrue);
      expect(config['whenResumeNotSupported'], 'fallback');
      expect(config.containsKey('maxAttempts'), isFalse);
      expect(config['enableVerboseLog'], isFalse);
      expect(config['enableStrongIntegrityValidation'], isFalse);
      expect(config['enableReadBackValidation'], isFalse);
      expect(config.containsKey('connectionTimeoutSeconds'), isFalse);
      expect(config.containsKey('uploadTimeoutMinutes'), isFalse);
      expect(config['retentionDays'], 7);
    });

    test('FTP includes optional ints and resume-fail mode', () {
      final config = configOf(
        draft(
          type: DestinationType.ftp,
          ftpPortText: '990',
          useFtps: true,
          ftpAllowInvalidCertificates: false,
          enableResumeFtp: false,
          keepPartOnCancelFtp: false,
          whenResumeNotSupportedFtp: FtpWhenResumeNotSupported.fail,
          ftpMaxAttemptsText: '5',
          enableVerboseLogFtp: true,
          enableStrongIntegrityValidationFtp: true,
          enableReadBackValidationFtp: true,
          ftpConnectionTimeoutSecondsText: '30',
          ftpUploadTimeoutMinutesText: '15',
        ),
      );

      expect(config['port'], 990);
      expect(config['useFtps'], isTrue);
      expect(config['allowInvalidCertificates'], isFalse);
      expect(config['enableResume'], isFalse);
      expect(config['keepPartOnCancel'], isFalse);
      expect(config['whenResumeNotSupported'], 'fail');
      expect(config['maxAttempts'], 5);
      expect(config['enableVerboseLog'], isTrue);
      expect(config['enableStrongIntegrityValidation'], isTrue);
      expect(config['enableReadBackValidation'], isTrue);
      expect(config['connectionTimeoutSeconds'], 30);
      expect(config['uploadTimeoutMinutes'], 15);
    });

    test('Google Drive uses root folderId', () {
      final destination = draft(
        type: DestinationType.googleDrive,
        googleFolderName: 'Client backups',
        retentionDays: 14,
      ).toDestination();

      expect(destination.type, DestinationType.googleDrive);
      expect(jsonDecode(destination.config), {
        'folderName': 'Client backups',
        'folderId': 'root',
        'retentionDays': 14,
      });
    });

    test('Dropbox maps folder path and name', () {
      expect(configOf(draft(type: DestinationType.dropbox)), {
        'folderPath': '/Apps',
        'folderName': 'Backups',
        'retentionDays': 7,
      });
    });

    test('Nextcloud keeps encrypted password and auth mode', () {
      final config = configOf(
        draft(
          type: DestinationType.nextcloud,
          nextcloudAuthMode: NextcloudAuthMode.userPassword,
          nextcloudRemotePath: '/Backups',
          nextcloudFolderName: 'DB',
          nextcloudAllowInvalidCertificates: true,
        ),
      );

      expect(config['serverUrl'], 'https://cloud.example.com');
      expect(config['username'], 'nc-user');
      expect(config['appPassword'], 'enc:app-pass');
      expect(config['authMode'], 'userPassword');
      expect(config['remotePath'], '/Backups');
      expect(config['folderName'], 'DB');
      expect(config['allowInvalidCertificates'], isTrue);
      expect(config['retentionDays'], 7);
    });
  });
}
