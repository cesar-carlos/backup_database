import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoogleDriveDestinationConfig', () {
    test('fromJson uses defaults for absent optional fields', () {
      final config = GoogleDriveDestinationConfig.fromJson({
        'folderId': 'root-folder',
      });

      expect(config.folderId, 'root-folder');
      expect(config.folderName, 'Backups');
      expect(config.accessToken, '');
      expect(config.refreshToken, '');
      expect(config.retentionDays, 30);
      expect(config.protectedBackupIdShortPrefixes, isEmpty);
    });

    group('copyWith', () {
      const base = GoogleDriveDestinationConfig(
        folderId: 'fid',
        folderName: 'Backups',
        accessToken: 'tok',
        refreshToken: 'ref',
      );

      test('no-op copy preserves all fields', () {
        final c = base.copyWith();
        expect(c.folderId, base.folderId);
        expect(c.folderName, base.folderName);
        expect(c.accessToken, base.accessToken);
        expect(c.refreshToken, base.refreshToken);
        expect(c.retentionDays, base.retentionDays);
      });

      test('overrides protectedBackupIdShortPrefixes (cleanup use case)', () {
        final c = base.copyWith(
          protectedBackupIdShortPrefixes: const {'abc12345'},
        );
        expect(c.protectedBackupIdShortPrefixes, equals(const {'abc12345'}));
        expect(c.folderId, base.folderId);
      });
    });
  });

  group('DropboxDestinationConfig', () {
    test('fromJson defaults folderPath to empty when absent', () {
      final config = DropboxDestinationConfig.fromJson({});
      expect(config.folderPath, '');
      expect(config.folderName, 'Backups');
      expect(config.retentionDays, 30);
    });

    group('copyWith', () {
      const base = DropboxDestinationConfig(folderPath: '/backups');

      test('overrides single field', () {
        final c = base.copyWith(retentionDays: 90);
        expect(c.retentionDays, 90);
        expect(c.folderPath, base.folderPath);
        expect(c.folderName, base.folderName);
      });

      test('propagates protectedBackupIdShortPrefixes', () {
        final c = base.copyWith(
          protectedBackupIdShortPrefixes: const {'def67890'},
        );
        expect(c.protectedBackupIdShortPrefixes, equals(const {'def67890'}));
      });
    });
  });

  group('NextcloudDestinationConfig', () {
    test('fromJson reads integrity flags with safe defaults', () {
      final config = NextcloudDestinationConfig.fromJson({
        'serverUrl': 'https://nc.example.com',
        'username': 'u',
        'appPassword': 'p',
      });

      expect(config.enableStrongIntegrityValidation, isFalse);
      expect(config.enableReadBackValidation, isFalse);
    });

    test('fromJson preserves explicit integrity flags', () {
      final config = NextcloudDestinationConfig.fromJson({
        'serverUrl': 'https://nc.example.com',
        'username': 'u',
        'appPassword': 'p',
        'enableStrongIntegrityValidation': true,
        'enableReadBackValidation': true,
      });

      expect(config.enableStrongIntegrityValidation, isTrue);
      expect(config.enableReadBackValidation, isTrue);
    });

    test('toJson includes integrity flags', () {
      final json = const NextcloudDestinationConfig(
        serverUrl: 'https://nc.example.com',
        username: 'u',
        appPassword: 'p',
        enableStrongIntegrityValidation: true,
        enableReadBackValidation: true,
      ).toJson();

      expect(json['enableStrongIntegrityValidation'], isTrue);
      expect(json['enableReadBackValidation'], isTrue);
    });

    group('copyWith', () {
      const base = NextcloudDestinationConfig(
        serverUrl: 'https://nc.example.com',
        username: 'u',
        appPassword: 'p',
      );

      test('no-op copy preserves all fields', () {
        final c = base.copyWith();
        expect(c.serverUrl, base.serverUrl);
        expect(c.username, base.username);
        expect(c.appPassword, base.appPassword);
        expect(c.authMode, base.authMode);
        expect(c.remotePath, base.remotePath);
        expect(c.folderName, base.folderName);
        expect(c.allowInvalidCertificates, base.allowInvalidCertificates);
        expect(c.retentionDays, base.retentionDays);
        expect(
          c.enableStrongIntegrityValidation,
          base.enableStrongIntegrityValidation,
        );
        expect(c.enableReadBackValidation, base.enableReadBackValidation);
      });

      test('propagates protectedBackupIdShortPrefixes', () {
        final c = base.copyWith(
          protectedBackupIdShortPrefixes: const {'xyz'},
        );
        expect(c.protectedBackupIdShortPrefixes, equals(const {'xyz'}));
      });

      test('flips integrity flags independently', () {
        final c = base.copyWith(
          enableStrongIntegrityValidation: true,
          enableReadBackValidation: true,
        );
        expect(c.enableStrongIntegrityValidation, isTrue);
        expect(c.enableReadBackValidation, isTrue);
        expect(c.allowInvalidCertificates, base.allowInvalidCertificates);
      });
    });
  });
}
