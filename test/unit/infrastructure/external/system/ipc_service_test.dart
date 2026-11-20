import 'dart:async';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/errors/service_connection_exception.dart';
import 'package:backup_database/core/utils/ipc_show_window_confirmation.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/infrastructure/external/system/ipc/in_memory_ipc_transport.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_channel.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

IpcService _pairedService() {
  return IpcService(transport: InMemoryIpcTransport());
}

class _UnavailableTransport implements IIpcTransport, IpcConnectionDiagnostics {
  @override
  String get lastConnectionFailure =>
      'peer_rejected reason=process_image_unavailable';
  @override
  Future<IIpcChannel?> connect({required Duration timeout}) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CloseFailureChannel implements IIpcChannel {
  _CloseFailureChannel({this.readError});
  final Error? readError;
  @override
  Future<void> writeLine(String line) async {}
  @override
  Future<String?> readLine({required Duration timeout}) async {
    if (readError != null) throw readError!;
    return '{"ok":true}';
  }

  @override
  Future<void> close() async => throw StateError('cleanup failed');
}

class _ChannelTransport extends _UnavailableTransport {
  _ChannelTransport(this.channel);
  final IIpcChannel channel;
  @override
  Future<IIpcChannel?> connect({required Duration timeout}) async => channel;
}

class _BlockedWriteChannel implements IIpcChannel {
  final pending = Completer<void>();
  bool closed = false;
  bool read = false;
  @override
  Future<void> writeLine(String line) => pending.future;
  @override
  Future<String?> readLine({required Duration timeout}) async {
    read = true;
    return '{"ok":true}';
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _GatedLifecycleTransport extends InMemoryIpcTransport {
  Completer<void>? startGate;
  Completer<void>? stopGate;
  final startEntered = Completer<void>();
  final stopEntered = Completer<void>();
  int starts = 0;

  @override
  Future<bool> startServer({
    required Future<void> Function(IIpcChannel channel) onConnection,
  }) async {
    starts++;
    if (!startEntered.isCompleted) startEntered.complete();
    await startGate?.future;
    return super.startServer(onConnection: onConnection);
  }

  @override
  Future<void> stopServer() async {
    if (!stopEntered.isCompleted) stopEntered.complete();
    await stopGate?.future;
    await super.stopServer();
  }
}

void main() {
  test('start during stop waits and creates a reachable new server', () async {
    final transport = _GatedLifecycleTransport();
    final ipc = IpcService(transport: transport);
    addTearDown(ipc.stop);
    await ipc.startServer(role: 'service');
    transport.stopGate = Completer<void>();
    final stop = ipc.stop();
    await transport.stopEntered.future;
    final restart = ipc.startServer(role: 'service');
    transport.stopGate!.complete();
    await stop;
    expect(await restart, isTrue);
    expect(ipc.isRunning, isTrue);
    expect(await ipc.checkServerRunning(), isTrue);
    expect(transport.starts, 2);
  });

  test('concurrent starts preserve the first activation callback', () async {
    final transport = _GatedLifecycleTransport()..startGate = Completer<void>();
    final ipc = IpcService(transport: transport);
    addTearDown(ipc.stop);
    var firstCalls = 0;
    var secondCalls = 0;
    final first = ipc.startServer(
      role: 'ui',
      onShowWindow: () async {
        firstCalls++;
        return true;
      },
    );
    await transport.startEntered.future;
    final second = ipc.startServer(
      role: 'ui',
      onShowWindow: () async {
        secondCalls++;
        return true;
      },
    );
    transport.startGate!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    await ipc.notifyExistingInstance();
    expect(firstCalls, 1);
    expect(secondCalls, 0);
    expect(transport.starts, 1);
  });

  test('failed start does not poison lifecycle queue', () async {
    final transport = _GatedLifecycleTransport()..startGate = Completer<void>();
    final ipc = IpcService(transport: transport);
    addTearDown(ipc.stop);
    final first = ipc.startServer(role: 'service');
    final failure = expectLater(first, throwsStateError);
    await transport.startEntered.future;
    transport.startGate!.completeError(StateError('spawn failed'));
    await failure;
    transport.startGate = null;
    expect(await ipc.startServer(role: 'service'), isTrue);
    expect(await ipc.checkServerRunning(), isTrue);
  });

  test('write timeout closes channel and remains uncertain even after late completion', () async {
    final channel = _BlockedWriteChannel();
    final service = IpcService(
      transport: _ChannelTransport(channel),
      writeTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      service.schedulerRequest('execute', 'attempt'),
      throwsA(isA<TimeoutException>()),
    );
    expect(channel.closed, isTrue);
    expect(channel.read, isFalse);
    channel.pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(channel.read, isFalse);
  });

  test('window activation also releases a stalled write', () async {
    final channel = _BlockedWriteChannel();
    final service = IpcService(
      transport: _ChannelTransport(channel),
      writeTimeout: const Duration(milliseconds: 10),
    );
    expect(
      await service.notifyExistingInstance(),
      SingleInstanceShowWindowStatus.notDelivered,
    );
    expect(channel.closed, isTrue);
    channel.pending.completeError(StateError('late write failure'));
    await Future<void>.delayed(Duration.zero);
  });
  test('close failure does not replace a confirmed execution result', () async {
    final service = IpcService(
      transport: _ChannelTransport(_CloseFailureChannel()),
    );
    expect(await service.schedulerRequest('execute', 'attempt'), {'ok': true});
  });

  test('close failure preserves the original read failure', () async {
    final failure = StateError('read failed');
    final service = IpcService(
      transport: _ChannelTransport(_CloseFailureChannel(readError: failure)),
    );
    await expectLater(
      service.schedulerRequest('execute', 'attempt'),
      throwsA(same(failure)),
    );
  });
  test(
    'scheduler preserves the transport diagnostic without sending work',
    () async {
      final service = IpcService(transport: _UnavailableTransport());
      await expectLater(
        service.schedulerRequest('execute', 'secret-payload'),
        throwsA(
          isA<ServiceConnectionException>()
              .having(
                (e) => e.reason,
                'reason',
                contains('process_image_unavailable'),
              )
              .having(
                (e) => e.toString(),
                'no payload',
                isNot(contains('secret-payload')),
              ),
        ),
      );
    },
  );
  const validScheduleId = '00000000-0000-4000-8000-000000000001';

  test(
    'unopened scheduler channel reports a request that was not sent',
    () async {
      final ipc = _pairedService();
      await expectLater(
        ipc.schedulerRequest('execute', validScheduleId),
        throwsA(isA<ServiceConnectionException>()),
      );
    },
  );

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
    setUp(IpcShowWindowConfirmation.resetForTest);

    test(
      'concurrent requests cannot borrow another request confirmation',
      () async {
        final ipc = _pairedService();
        final firstEntered = Completer<void>();
        final secondEntered = Completer<void>();
        final finishFirst = Completer<void>();
        final finishSecond = Completer<void>();
        var count = 0;
        await ipc.startServer(
          role: SingleInstanceConfig.ipcInstanceRoleUi,
          onShowWindow: () async {
            if (++count == 1) {
              firstEntered.complete();
              await finishFirst.future;
              IpcShowWindowConfirmation.markShown();
            } else {
              secondEntered.complete();
              await finishSecond.future;
            }
            return null;
          },
        );
        try {
          final first = ipc.notifyExistingInstance();
          await firstEntered.future;
          final second = ipc.notifyExistingInstance();
          await secondEntered.future;
          finishFirst.complete();
          expect(await first, SingleInstanceShowWindowStatus.shown);
          finishSecond.complete();
          expect(await second, SingleInstanceShowWindowStatus.unavailable);
        } finally {
          if (!finishFirst.isCompleted) finishFirst.complete();
          if (!finishSecond.isCompleted) finishSecond.complete();
          await ipc.stop();
        }
      },
    );

    test('waits for slow native restoration before acknowledging', () async {
      final ipc = _pairedService();
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleUi,
        onShowWindow: () async {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          IpcShowWindowConfirmation.markShown();
          return null;
        },
      );
      try {
        expect(
          await ipc.notifyExistingInstance(),
          SingleInstanceShowWindowStatus.shown,
        );
      } finally {
        await ipc.stop();
      }
    });

    test('should ACK SHOW_WINDOW only after the window is shown', () async {
      final ipc = _pairedService();
      var showCount = 0;
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleUi,
        onShowWindow: () async {
          showCount++;
          IpcShowWindowConfirmation.markShown();
          return null;
        },
      );

      try {
        expect(
          await ipc.notifyExistingInstance(),
          SingleInstanceShowWindowStatus.shown,
        );
        expect(showCount, 1);
      } finally {
        await ipc.stop();
      }
    });

    test('should report unavailable when the callback does not show', () async {
      final ipc = _pairedService();
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleUi,
        onShowWindow: () async {
          return null;
        },
      );

      try {
        expect(
          await ipc.notifyExistingInstance(),
          SingleInstanceShowWindowStatus.unavailable,
        );
      } finally {
        await ipc.stop();
      }
    });

    test(
      'should report unavailable when no show callback is registered',
      () async {
        final ipc = _pairedService();
        await ipc.startServer(
          role: SingleInstanceConfig.ipcInstanceRoleService,
        );

        try {
          expect(
            await ipc.notifyExistingInstance(),
            SingleInstanceShowWindowStatus.unavailable,
          );
        } finally {
          await ipc.stop();
        }
      },
    );

    test('should not ACK when SHOW_WINDOW callback throws', () async {
      final ipc = _pairedService();
      await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleUi,
        onShowWindow: () async {
          throw StateError('window boom');
        },
      );

      try {
        expect(
          await ipc.notifyExistingInstance(),
          isNot(SingleInstanceShowWindowStatus.shown),
        );
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
          expect(
            await ipc.notifyExistingInstance(),
            SingleInstanceShowWindowStatus.notDelivered,
          );
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
