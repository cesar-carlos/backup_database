import 'dart:convert';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_v1_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validScheduleId = '00000000-0000-4000-8000-000000000001';

  group('IpcV1Codec.hasProtocolVersion', () {
    test('should accept v=1 as a field', () {
      expect(
        IpcV1Codec.hasProtocolVersion(
          'BACKUP_DATABASE_IPC_V1|PONG|v=1|role=ui',
        ),
        isTrue,
      );
    });

    test('should reject v=10 which contains v=1 as substring', () {
      expect(
        IpcV1Codec.hasProtocolVersion(
          'BACKUP_DATABASE_IPC_V1|PONG|v=10|role=ui',
        ),
        isFalse,
      );
    });
  });

  group('IpcV1Codec.parseRunScheduleRequest', () {
    test('should parse a v1 UUID schedule id', () {
      final line = SingleInstanceConfig.ipcRunScheduleMessage(validScheduleId);

      expect(IpcV1Codec.parseRunScheduleRequest(line), validScheduleId);
    });

    test('should reject missing protocol prefix', () {
      expect(
        IpcV1Codec.parseRunScheduleRequest('scheduleId=$validScheduleId'),
        isNull,
      );
    });

    test('should reject invalid uuid', () {
      const line =
          '${SingleInstanceConfig.ipcProtocolId}|'
          '${SingleInstanceConfig.ipcRunScheduleCommand}|'
          'v=1|scheduleId=not-a-uuid';

      expect(IpcV1Codec.parseRunScheduleRequest(line), isNull);
    });

    test('should reject missing version field', () {
      const line =
          '${SingleInstanceConfig.ipcProtocolId}|'
          '${SingleInstanceConfig.ipcRunScheduleCommand}|'
          'scheduleId=$validScheduleId';

      expect(IpcV1Codec.parseRunScheduleRequest(line), isNull);
    });
  });

  group('IpcV1Codec.parseRunScheduleResult', () {
    test('should round-trip exit code and message64', () {
      final line = IpcV1Codec.buildRunScheduleResultLine(
        exitCode: 2,
        message: 'invalid_schedule_id',
      );

      final result = IpcV1Codec.parseRunScheduleResult(line);

      expect(result, isNotNull);
      expect(result!.exitCode, 2);
      expect(result.message, 'invalid_schedule_id');
    });

    test('should reject v=10 result lines', () {
      final line =
          '${SingleInstanceConfig.ipcRunScheduleResultLinePrefix}'
          'v=10|exitCode=0';

      expect(IpcV1Codec.parseRunScheduleResult(line), isNull);
    });
  });

  group('IpcV1Codec.parseUserInfoResponse', () {
    test('should decode u64 username', () {
      final u64 = base64Url.encode(utf8.encode('alice'));
      final line =
          '${SingleInstanceConfig.ipcUserInfoLinePrefix}'
          'v=1|role=ui|pid=1|u64=$u64';

      expect(IpcV1Codec.parseUserInfoResponse(line), 'alice');
    });

    test('should ignore legacy USER_INFO prefix', () {
      expect(IpcV1Codec.parseUserInfoResponse('USER_INFO:alice'), isNull);
    });
  });

  group('IpcV1Codec SHOW_WINDOW ACK', () {
    test('should recognize protocol OK ack', () {
      expect(
        IpcV1Codec.isOkAck(SingleInstanceConfig.ipcOkAckMessage),
        isTrue,
      );
      expect(IpcV1Codec.isOkAck('OK'), isFalse);
      expect(IpcV1Codec.isOkAck(null), isFalse);
    });
  });

  group('IpcV1Codec line helpers', () {
    test('should strip CR LF from a framed line', () {
      expect(
        IpcV1Codec.stripLine('${SingleInstanceConfig.ipcOkAckMessage}\r\n'),
        SingleInstanceConfig.ipcOkAckMessage,
      );
    });

    test('should flag buffers larger than ipcMaxLineBytes', () {
      final over = List<int>.filled(
        SingleInstanceConfig.ipcMaxLineBytes + 1,
        65,
      );
      expect(IpcV1Codec.exceedsMaxLineBytes(over), isTrue);
      expect(
        IpcV1Codec.exceedsMaxLineBytes(
          List<int>.filled(SingleInstanceConfig.ipcMaxLineBytes, 65),
        ),
        isFalse,
      );
    });
  });

  group('IpcV1Codec.pong', () {
    test('should parse owner info from a valid pong', () {
      final line = IpcV1Codec.buildV1PongLine(
        role: SingleInstanceConfig.ipcInstanceRoleService,
        canRunSchedule: true,
      );

      final info = IpcV1Codec.parseOwnerInfoFromV1Pong(line);

      expect(info, isNotNull);
      expect(info!.role, SingleInstanceConfig.ipcInstanceRoleService);
      expect(info.canRunSchedule, isTrue);
    });

    test('should reject pong without version field', () {
      final line = '${SingleInstanceConfig.ipcPongLinePrefix}role=ui|pid=1';

      expect(IpcV1Codec.isValidV1Pong(line), isFalse);
    });
  });
}
