import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'SocketLoggerService.redactPayloadForLog (§audit-2026-05-28 wave 2)',
    () {
      test('redacts passwordHash from authRequest', () {
        // Mesmo o hash PBKDF2 é informação suficiente para um ataque de
        // dicionário offline contra uma `serverId` conhecida — proibimos
        // gravar em disco.
        final redacted = SocketLoggerService.redactPayloadForLog(
          MessageType.authRequest,
          {
            'serverId': 'srv-123',
            'passwordHash': r'pbkdf2-sha256$10000$abc$xyz',
            'clientId': 'client-1',
          },
        );

        expect(redacted['passwordHash'], '***');
        expect(redacted['serverId'], 'srv-123');
        expect(redacted['clientId'], 'client-1');
      });

      test(
        'redacts password and cryptKey from createDatabaseConfigRequest',
        () {
          final redacted = SocketLoggerService.redactPayloadForLog(
            MessageType.createDatabaseConfigRequest,
            {
              'host': '10.0.0.1',
              'username': 'sa',
              'password': 'P@ssw0rd!',
              'cryptKey': 'aes-key-12345',
            },
          );

          expect(redacted['password'], '***');
          expect(redacted['cryptKey'], '***');
          expect(redacted['username'], 'sa');
          expect(redacted['host'], '10.0.0.1');
        },
      );

      test('redacts password from testDatabaseConnectionRequest', () {
        final redacted = SocketLoggerService.redactPayloadForLog(
          MessageType.testDatabaseConnectionRequest,
          {
            'host': '10.0.0.1',
            'password': 'secret',
          },
        );

        expect(redacted['password'], '***');
      });

      test('leaves non-sensitive types untouched (e.g. heartbeat)', () {
        final original = {'pingId': 42, 'timestamp': 1748448000000};
        final redacted = SocketLoggerService.redactPayloadForLog(
          MessageType.heartbeat,
          original,
        );

        expect(identical(redacted, original), isTrue);
      });

      test('preserves keys that are NOT in the sensitive list', () {
        final redacted = SocketLoggerService.redactPayloadForLog(
          MessageType.authRequest,
          {
            'serverId': 'srv',
            'passwordHash': 'leak',
            'protocolVersion': 2,
          },
        );

        expect(redacted['protocolVersion'], 2);
        expect(redacted['passwordHash'], '***');
      });
    },
  );
}
