import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FtpDestinationConfig', () {
    Map<String, dynamic> minimalJson() => {
      'host': 'ftp.example.com',
      'username': 'user',
      'password': 'pass',
      'remotePath': '/backups',
    };

    test(
      'fromJson uses large-file friendly defaults when fields are absent',
      () {
        final config = FtpDestinationConfig.fromJson(minimalJson());

        expect(config.enableStrongIntegrityValidation, isFalse);
        expect(config.enableReadBackValidation, isFalse);
        expect(config.allowInvalidCertificates, isTrue);
      },
    );

    test('fromJson preserves explicit integrity and certificate settings', () {
      final config = FtpDestinationConfig.fromJson({
        ...minimalJson(),
        'enableStrongIntegrityValidation': true,
        'enableReadBackValidation': true,
        'allowInvalidCertificates': false,
      });

      expect(config.enableStrongIntegrityValidation, isTrue);
      expect(config.enableReadBackValidation, isTrue);
      expect(config.allowInvalidCertificates, isFalse);
    });

    test('toJson includes FTPS certificate and integrity settings', () {
      final json = const FtpDestinationConfig(
        host: 'ftp.example.com',
        username: 'user',
        password: 'pass',
        remotePath: '/backups',
        enableStrongIntegrityValidation: true,
        enableReadBackValidation: true,
        allowInvalidCertificates: false,
      ).toJson();

      expect(json['enableStrongIntegrityValidation'], isTrue);
      expect(json['enableReadBackValidation'], isTrue);
      expect(json['allowInvalidCertificates'], isFalse);
    });

    test('fromJson defaults remotePath to "/" when field is absent', () {
      final config = FtpDestinationConfig.fromJson({
        'host': 'ftp.example.com',
        'username': 'user',
        'password': 'pass',
      });

      expect(config.remotePath, '/');
    });

    group('copyWith', () {
      const base = FtpDestinationConfig(
        host: 'ftp.example.com',
        username: 'user',
        password: 'pass',
        remotePath: '/backups',
      );

      test('returns equivalent values when no override is provided', () {
        final copy = base.copyWith();

        expect(copy.host, base.host);
        expect(copy.port, base.port);
        expect(copy.username, base.username);
        expect(copy.password, base.password);
        expect(copy.remotePath, base.remotePath);
        expect(copy.useFtps, base.useFtps);
        expect(copy.retentionDays, base.retentionDays);
        expect(copy.enableResume, base.enableResume);
        expect(copy.keepPartOnCancel, base.keepPartOnCancel);
        expect(copy.maxAttempts, base.maxAttempts);
        expect(copy.whenResumeNotSupported, base.whenResumeNotSupported);
        expect(copy.enableVerboseLog, base.enableVerboseLog);
        expect(copy.connectionTimeoutSeconds, base.connectionTimeoutSeconds);
        expect(copy.uploadTimeoutMinutes, base.uploadTimeoutMinutes);
        expect(
          copy.enableStrongIntegrityValidation,
          base.enableStrongIntegrityValidation,
        );
        expect(copy.enableReadBackValidation, base.enableReadBackValidation);
        expect(copy.allowInvalidCertificates, base.allowInvalidCertificates);
        expect(
          copy.protectedBackupIdShortPrefixes,
          base.protectedBackupIdShortPrefixes,
        );
      });

      test('propagates protectedBackupIdShortPrefixes (cleanup use case)', () {
        final copy = base.copyWith(
          protectedBackupIdShortPrefixes: const {'abc12345', 'def67890'},
        );

        expect(
          copy.protectedBackupIdShortPrefixes,
          equals(const {'abc12345', 'def67890'}),
        );
        expect(copy.host, base.host);
        expect(copy.remotePath, base.remotePath);
      });

      test('overrides a single field without touching the others', () {
        final copy = base.copyWith(
          host: 'ftp.other.com',
          useFtps: true,
          enableStrongIntegrityValidation: true,
        );

        expect(copy.host, 'ftp.other.com');
        expect(copy.useFtps, isTrue);
        expect(copy.enableStrongIntegrityValidation, isTrue);
        expect(copy.username, base.username);
        expect(copy.password, base.password);
        expect(copy.remotePath, base.remotePath);
      });
    });
  });
}
