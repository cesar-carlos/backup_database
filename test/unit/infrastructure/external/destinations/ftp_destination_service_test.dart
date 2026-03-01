import 'dart:io';

import 'package:backup_database/core/errors/failure.dart' hide FtpFailure;
import 'package:backup_database/core/errors/ftp_failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp_destination_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late FtpDestinationService service;

  setUp(() {
    service = FtpDestinationService();
  });

  group('FtpDestinationService.upload', () {
    test('returns Failure when source file does not exist', () async {
      const config = FtpDestinationConfig(
        host: 'ftp.example.com',
        username: 'u',
        password: 'p',
        remotePath: '/',
      );

      final result = await service.upload(
        sourceFilePath: '/nonexistent/path/backup.bak',
        config: config,
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (f) {
          final failure = f as FileSystemFailure;
          expect(failure.message, contains('não encontrado'));
        },
      );
    });

    test('returns Failure with connection error when host unreachable', () async {
      final tempDir = await Directory.systemTemp.createTemp('ftp_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final testFile = File(p.join(tempDir.path, 'test.bak'));
      await testFile.writeAsString('test content');

      const config = FtpDestinationConfig(
        host: '127.0.0.1',
        port: 29999,
        username: 'u',
        password: 'p',
        remotePath: '/',
      );

      final result = await service.upload(
        sourceFilePath: testFile.path,
        config: config,
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (f) {
          expect(f, isA<FtpFailure>());
          final failure = f as FtpFailure;
          expect(
            failure.message.toLowerCase(),
            anyOf(
              contains('conexão'),
              contains('connection'),
              contains('timeout'),
              contains('recusad'),
              contains('refused'),
            ),
          );
        },
      );
    });
  });

  group('FtpDestinationService.testConnection', () {
    test('returns Failure when host unreachable', () async {
      const config = FtpDestinationConfig(
        host: '127.0.0.1',
        port: 29998,
        username: 'u',
        password: 'p',
        remotePath: '/',
      );

      final result = await service.testConnection(config);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (f) {
          expect(f, isA<FtpFailure>());
        },
      );
    });
  });
}
