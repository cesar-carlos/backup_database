import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Backup messages with optional runId (M2.3)', () {
    group('createBackupProgressMessage', () {
      test('omite runId quando nao fornecido (comportamento v1 preservado)',
          () {
        final msg = createBackupProgressMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          step: 'Iniciando',
          message: 'Iniciando backup',
        );

        expect(msg.header.type, MessageType.backupProgress);
        expect(msg.payload.containsKey('runId'), isFalse);
        expect(getRunIdFromBackupMessage(msg), isNull);
      });

      test('inclui runId quando fornecido (comportamento v2)', () {
        const runId = 'schedule-1_uuid-abc';
        final msg = createBackupProgressMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          step: 'Executando',
          message: 'em andamento',
          progress: 0.5,
          runId: runId,
        );

        expect(msg.payload['runId'], runId);
        expect(getRunIdFromBackupMessage(msg), runId);
      });
    });

    group('createBackupCompleteMessage', () {
      test('omite runId por padrao', () {
        final msg = createBackupCompleteMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
        );
        expect(msg.payload.containsKey('runId'), isFalse);
        expect(getRunIdFromBackupMessage(msg), isNull);
      });

      test('inclui runId quando fornecido', () {
        const runId = 'schedule-1_uuid-xyz';
        final msg = createBackupCompleteMessage(
          requestId: 2,
          scheduleId: 'schedule-1',
          backupPath: '/tmp/backup.zip',
          runId: runId,
        );
        expect(msg.payload['runId'], runId);
        expect(getRunIdFromBackupMessage(msg), runId);
      });
    });

    group('createBackupFailedMessage', () {
      test('omite runId por padrao', () {
        final msg = createBackupFailedMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          error: 'falha',
        );
        expect(msg.payload.containsKey('runId'), isFalse);
        expect(getRunIdFromBackupMessage(msg), isNull);
      });

      test('inclui runId quando fornecido', () {
        const runId = 'schedule-1_uuid-fail';
        final msg = createBackupFailedMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          error: 'falha',
          runId: runId,
        );
        expect(msg.payload['runId'], runId);
        expect(getRunIdFromBackupMessage(msg), runId);
      });
    });

    group('getRunIdFromBackupMessage backward compat', () {
      test('retorna null para mensagem sem campo runId (servidor v1)', () {
        // Simula payload de servidor v1 que nao conhece M2.3
        final legacyPayload = <String, dynamic>{
          'scheduleId': 'schedule-1',
          'step': 'Iniciando',
          'message': 'algo',
          'progress': 0.0,
        };
        final msg = Message(
          header: MessageHeader(
            type: MessageType.backupProgress,
            length: 0,
            requestId: 1,
          ),
          payload: legacyPayload,
          checksum: 0,
        );

        expect(getRunIdFromBackupMessage(msg), isNull);
      });

      test('retorna valor para mensagem com runId (servidor v2)', () {
        final v2Payload = <String, dynamic>{
          'scheduleId': 'schedule-1',
          'step': 'Iniciando',
          'message': 'algo',
          'progress': 0.0,
          'runId': 'schedule-1_uuid-1',
        };
        final msg = Message(
          header: MessageHeader(
            type: MessageType.backupProgress,
            length: 0,
            requestId: 1,
          ),
          payload: v2Payload,
          checksum: 0,
        );

        expect(getRunIdFromBackupMessage(msg), 'schedule-1_uuid-1');
      });
    });

    test(
      'wire format: tamanho do payload aumenta apenas quando runId presente',
      () {
        final without = createBackupProgressMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          step: 'Iniciando',
          message: 'msg',
        );
        final with_ = createBackupProgressMessage(
          requestId: 1,
          scheduleId: 'schedule-1',
          step: 'Iniciando',
          message: 'msg',
          runId: 'schedule-1_uuid-z',
        );

        // Mensagem sem runId nao deve carregar overhead extra
        expect(without.header.length, lessThan(with_.header.length));
        expect(without.payload.containsKey('runId'), isFalse);
        expect(with_.payload['runId'], 'schedule-1_uuid-z');
      },
    );
  });
}
