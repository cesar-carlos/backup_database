import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/infrastructure/external/system/ipc/in_memory_ipc_transport.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

IpcService _pairedService() {
  return IpcService(transport: InMemoryIpcTransport());
}

void main() {
  const validScheduleId = '00000000-0000-4000-8000-000000000001';

  group('IpcService.checkServerRunning', () {
    test(
      'should return true when server responds with valid V1 PONG',
      () async {
        final ipc = _pairedService();
        final started = await ipc.startServer(
          role: SingleInstanceConfig.ipcInstanceRoleUi,
        );
        expect(started, isTrue);

        try {
          expect(await ipc.checkServerRunning(), isTrue);
        } finally {
          await ipc.stop();
        }
      },
    );

    test('should return false when no server is listening', () async {
      final ipc = _pairedService();

      expect(await ipc.checkServerRunning(), isFalse);
    });
  });

  group('IpcService.getExistingInstanceInfo', () {
    test('should parse V1 PONG role and schedule capability', () async {
      final ipc = _pairedService();
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleService,
        onRunSchedule: (_) async => 0,
      );

      try {
        final info = await ipc.getExistingInstanceInfo();

        expect(info, isNotNull);
        expect(info!.role, SingleInstanceConfig.ipcInstanceRoleService);
        expect(info.canRunSchedule, isTrue);
      } finally {
        await ipc.stop();
      }
    });

    test(
      'should default schedule capability to false without handler',
      () async {
        final ipc = _pairedService();
        await ipc.startServer(
          role: SingleInstanceConfig.ipcInstanceRoleUi,
        );

        try {
          final info = await ipc.getExistingInstanceInfo();

          expect(info, isNotNull);
          expect(info!.role, SingleInstanceConfig.ipcInstanceRoleUi);
          expect(info.canRunSchedule, isFalse);
        } finally {
          await ipc.stop();
        }
      },
    );
  });

  group('IpcService.getExistingInstanceUser', () {
    test('should return a username from V1 USER_INFO', () async {
      final ipc = _pairedService();
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleUi,
      );

      try {
        final result = await ipc.getExistingInstanceUser();

        expect(result, isNotNull);
        expect(result, isNotEmpty);
      } finally {
        await ipc.stop();
      }
    });
  });

  group('IpcService SHOW_WINDOW', () {
    test('should ACK SHOW_WINDOW after invoking the callback', () async {
      final ipc = _pairedService();
      var showCount = 0;
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleUi,
        onShowWindow: () async {
          showCount++;
        },
      );

      try {
        expect(await ipc.notifyExistingInstance(), isTrue);
        expect(showCount, 1);
      } finally {
        await ipc.stop();
      }
    });

    test('should not ACK when SHOW_WINDOW callback throws', () async {
      final ipc = _pairedService();
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleUi,
        onShowWindow: () async {
          throw StateError('window boom');
        },
      );

      try {
        expect(await ipc.notifyExistingInstance(), isFalse);
      } finally {
        await ipc.stop();
      }
    });
  });

  group('IpcService RUN_SCHEDULE', () {
    test('should delegate RUN_SCHEDULE and return exit code', () async {
      final ipc = _pairedService();
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleService,
        onRunSchedule: (scheduleId) async {
          expect(scheduleId, validScheduleId);
          return 0;
        },
      );

      try {
        final result = await ipc.delegateScheduledExecution(validScheduleId);

        expect(result, isNotNull);
        expect(result!.exitCode, 0);
        expect(result.message, SingleInstanceConfig.ipcRunScheduleMessageOk);
      } finally {
        await ipc.stop();
      }
    });

    test(
      'should return owner cannot run schedule when server lacks handler',
      () async {
        final ipc = _pairedService();
        await ipc.startServer(
          role: SingleInstanceConfig.ipcInstanceRoleUi,
        );

        try {
          final result = await ipc.delegateScheduledExecution(validScheduleId);

          expect(result, isNotNull);
          expect(result!.exitCode, 1);
          expect(
            result.message,
            SingleInstanceConfig.ipcRunScheduleMessageOwnerCannotRunSchedule,
          );
        } finally {
          await ipc.stop();
        }
      },
    );

    test('should reject invalid schedule id before the handler', () async {
      final ipc = _pairedService();
      var handlerCalls = 0;
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleService,
        onRunSchedule: (_) async {
          handlerCalls++;
          return 0;
        },
      );

      try {
        final result = await ipc.delegateScheduledExecution('not-a-uuid');

        expect(result, isNotNull);
        expect(result!.exitCode, 2);
        expect(
          result.message,
          SingleInstanceConfig.ipcRunScheduleMessageInvalidScheduleId,
        );
        expect(handlerCalls, 0);
      } finally {
        await ipc.stop();
      }
    });

    test(
      'should return timeout result when RUN_SCHEDULE owner does not reply',
      () async {
        dotenv.loadFromString(
          envString: 'SCHEDULED_DELEGATION_TIMEOUT_SECONDS=1',
        );
        final transport = InMemoryIpcTransport();
        await transport.startServer(
          onConnection: (channel) async {
            await channel.readLine(
              timeout: const Duration(seconds: 5),
            );
          },
        );
        final client = IpcService(transport: transport);

        try {
          final result = await client.delegateScheduledExecution(
            validScheduleId,
          );

          expect(result, isNotNull);
          expect(result!.exitCode, 1);
          expect(
            result.message,
            SingleInstanceConfig.ipcRunScheduleMessageDelegationTimeout,
          );
        } finally {
          dotenv.loadFromString(envString: 'OTHER_KEY=value');
          await transport.stopServer();
        }
      },
    );
  });

  group('IpcService.startServer / stop', () {
    test('should return false when the transport cannot listen', () async {
      final ipc = IpcService(
        transport: InMemoryIpcTransport(failStart: true),
      );

      final started = await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleUi,
      );

      expect(started, isFalse);
      expect(ipc.isRunning, isFalse);
      expect(await ipc.checkServerRunning(), isFalse);
    });

    test(
      'should refuse a new connection when the instance limit is reached',
      () async {
        final transport = InMemoryIpcTransport(maxInstances: 0);
        final ipc = IpcService(transport: transport);
        await ipc.startServer(role: SingleInstanceConfig.ipcInstanceRoleUi);

        try {
          expect(await ipc.notifyExistingInstance(), isFalse);
        } finally {
          await ipc.stop();
        }
      },
    );

    test('should report not running after stop even if close throws', () async {
      final ipc = IpcService(
        transport: InMemoryIpcTransport(throwOnStop: true),
      );
      await ipc.startServer(role: SingleInstanceConfig.ipcInstanceRoleUi);
      await ipc.stop();

      expect(ipc.isRunning, isFalse);
      expect(await ipc.checkServerRunning(), isFalse);
    });
  });
}
