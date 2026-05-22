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
  });
}
