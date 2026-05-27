import 'dart:async';
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

    test(
      'returns Failure with connection error when host unreachable',
      () async {
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
      },
    );
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

  group('FtpDestinationService.getFtpErrorMessage', () {
    const host = 'ftp.example.com';

    test('TimeoutException maps to "Tempo limite excedido"', () {
      final msg = FtpDestinationService.getFtpErrorMessage(
        TimeoutException('op timed out'),
        host,
      );
      expect(msg, contains('Tempo limite excedido'));
      expect(msg, contains(host));
    });

    test('SocketException maps to connection error', () {
      final msg = FtpDestinationService.getFtpErrorMessage(
        const SocketException('Connection refused'),
        host,
      );
      expect(msg, contains('Erro de conexão'));
      expect(msg, contains(host));
    });

    test('TlsException maps to TLS error', () {
      final msg = FtpDestinationService.getFtpErrorMessage(
        const TlsException('bad cert'),
        host,
      );
      expect(msg, contains('TLS/SSL'));
    });

    test('HandshakeException maps to TLS error', () {
      final msg = FtpDestinationService.getFtpErrorMessage(
        const HandshakeException('handshake failed'),
        host,
      );
      expect(msg, contains('TLS/SSL'));
    });

    test('FTP 530 in error string maps to authentication error', () {
      final msg = FtpDestinationService.getFtpErrorMessage(
        Exception('FTP Response: 530 Login authentication failed.'),
        host,
      );
      expect(msg, contains('autenticação'));
    });

    test('FTP 550 in error string maps to permission error', () {
      final msg = FtpDestinationService.getFtpErrorMessage(
        Exception('FTP Response: 550 Permission denied.'),
        host,
      );
      expect(msg, contains('permissão'));
    });

    test('FTP 452 in error string maps to disk space error', () {
      final msg = FtpDestinationService.getFtpErrorMessage(
        Exception('452 Insufficient storage space.'),
        host,
      );
      expect(msg, contains('espaço em disco'));
    });

    test(
      'unrelated digit sequences containing 530/550/452 do NOT match codes',
      () {
        // "11530" e "5500" não são códigos FTP isolados — devem cair no
        // fallback genérico.
        final msg = FtpDestinationService.getFtpErrorMessage(
          Exception('unexpected error 11530 internal id 5500 buf 4520'),
          host,
        );
        expect(msg, contains('Erro no upload FTP'));
        expect(msg, isNot(contains('autenticação')));
        expect(msg, isNot(contains('permissão')));
        expect(msg, isNot(contains('espaço em disco')));
      },
    );

    test('"hostname" substring matches as connection error', () {
      final msg = FtpDestinationService.getFtpErrorMessage(
        Exception('Unknown hostname'),
        host,
      );
      expect(msg, contains('Erro de conexão'));
    });

    test('unknown error falls back to generic message', () {
      final msg = FtpDestinationService.getFtpErrorMessage(
        Exception('something unexpected'),
        host,
      );
      expect(msg, contains('Erro no upload FTP'));
      expect(msg, contains(host));
    });
  });

  group('FtpDestinationService.buildRemotePartName', () {
    test('uses runId + destinationId when both are provided', () {
      final name = FtpDestinationService.buildRemotePartName(
        finalFileName: 'backup.bak',
        runId: 'run123',
        destinationId: 'dest456',
      );
      expect(name, 'backup.bak.run123_dest456.part');
    });

    test('uses runId only when destinationId is empty', () {
      final name = FtpDestinationService.buildRemotePartName(
        finalFileName: 'backup.bak',
        runId: 'run123',
        destinationId: '',
      );
      expect(name, 'backup.bak.run123.part');
    });

    test('sanitizes unsafe characters from token', () {
      final name = FtpDestinationService.buildRemotePartName(
        finalFileName: 'backup.bak',
        runId: 'run/123',
        destinationId: 'dest:456',
      );
      expect(name, 'backup.bak.run_123_dest_456.part');
    });

    test(
      'fallback (no runId/destinationId) generates unique names even '
      'when called within the same millisecond',
      () {
        final names = List.generate(
          50,
          (_) => FtpDestinationService.buildRemotePartName(
            finalFileName: 'backup.bak',
          ),
        ).toSet();
        // Sem o sufixo aleatório, vários nomes colidiriam no mesmo ms.
        expect(names.length, equals(50));
      },
    );
  });
}
