import 'dart:async';
import 'dart:convert';

import 'package:backup_database/application/services/service_scheduler_proxy.dart';
import 'package:backup_database/core/config/execution_ownership.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/service_connection_exception.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/admin_scheduler_endpoint.dart';
import 'package:backup_database/infrastructure/external/system/ipc/in_memory_ipc_transport.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _Scheduler extends Mock
    implements ISchedulerService, IScopedBackupCancellation {}

void main() {
  test('automatic admin launch is suppressed but manual launch is allowed', () {
    ExecutionOwnership.administrativeUi = true;
    addTearDown(() => ExecutionOwnership.administrativeUi = false);
    expect(
      ExecutionOwnership.suppressAutomaticUi(automaticLaunch: true),
      isTrue,
    );
    expect(
      ExecutionOwnership.suppressAutomaticUi(automaticLaunch: false),
      isFalse,
    );
  });
  const id = '00000000-0000-4000-8000-000000000001';
  late _Scheduler scheduler;
  late IpcService ipc;
  late ServiceSchedulerProxy ui;

  setUp(() async {
    scheduler = _Scheduler();
    when(() => scheduler.isExecutingBackup).thenReturn(false);
    ipc = IpcService(transport: InMemoryIpcTransport())..scheduler = scheduler;
    await ipc.startServer(role: 'service');
    ui = ServiceSchedulerProxy(ipc.schedulerRequest);
  });
  tearDown(() async => ipc.stop());

  test('stop releases pending status and ignores its late success', () async {
    final status = Completer<Map<String, dynamic>>();
    final commands = <String>[];
    final proxy = ServiceSchedulerProxy((command, _) {
      commands.add(command);
      return status.future;
    });
    final work = proxy.executeNow(id);
    proxy.stop();
    expect((await work.timeout(const Duration(seconds: 1))).isError(), isTrue);
    expect(proxy.isExecutingBackup, isFalse);
    status.complete({'ok': true, 'epoch': 'old-service'});
    await Future<void>.delayed(Duration.zero);
    expect(commands, ['status']);
  });

  test(
    'late status error after stop is handled and next attempt can recover',
    () async {
      final status = Completer<Map<String, dynamic>>();
      var first = true;
      final commands = <String>[];
      final proxy = ServiceSchedulerProxy((command, _) async {
        commands.add(command);
        if (first) {
          first = false;
          return status.future;
        }
        return command == 'status'
            ? {'ok': true, 'epoch': 'new-service'}
            : {'ok': true};
      });
      final work = proxy.executeNow(id);
      proxy.stop();
      expect(
        (await work.timeout(const Duration(seconds: 1))).isError(),
        isTrue,
      );
      status.completeError(StateError('old connection failed'));
      await Future<void>.delayed(Duration.zero);
      expect((await proxy.executeNow(id)).isSuccess(), isTrue);
      expect(commands, ['status', 'status', 'execute']);
    },
  );

  for (final reply in <Map<String, dynamic>>[
    {'ok': false, 'confirmed': true, 'error': 123},
    {'ok': true, 'uncertain': true},
    {'ok': true, 'uncertain': 'true'},
    {'ok': true, 'confirmed': 'true'},
  ]) {
    test('invalid receipt preserves attempt identity: $reply', () async {
      final requests = <String>[];
      final proxy = ServiceSchedulerProxy((command, payload) async {
        if (command == 'status') return {'ok': true, 'epoch': 'service'};
        requests.add(payload);
        return requests.length == 1 ? reply : {'ok': true};
      });
      final first = await proxy.executeNow(id);
      expect(first.isError(), isTrue);
      expect(
        (first.exceptionOrNull()! as BackupFailure).code,
        'service_execution_unconfirmed',
      );
      expect((await proxy.executeNow(id)).isSuccess(), isTrue);
      expect(requests.length, 2);
      expect(requests[1], requests[0]);
    });
  }

  test(
    'synchronous replay sees a receipt before executor code is invoked',
    () async {
      final endpoint = AdminSchedulerEndpoint()..scheduler = scheduler;
      final status = await endpoint.dispatch('status', '');
      final payload = jsonEncode({
        'scheduleId': id,
        'epoch': status['epoch'],
        'requestId': '00000000-0000-4000-8000-000000000002',
      });
      late Future<Map<String, dynamic>> replay;
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenAnswer((_) {
            replay = endpoint.dispatch('execute', payload);
            return Future.value(const rd.Success(rd.unit));
          });
      expect((await endpoint.dispatch('execute', payload))['ok'], isTrue);
      expect((await replay)['ok'], isTrue);
      verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .called(1);
    },
  );

  test(
    'executor exception is logged once with run identity and replayed',
    () async {
      final messages = <String>[];
      final errors = <Object>[];
      final failure = StateError('underlying executor failure');
      final endpoint = AdminSchedulerEndpoint(
        logError: (message, error, stack) {
          messages.add(message);
          errors.add(error);
          expect(stack.toString(), isNotEmpty);
        },
      )..scheduler = scheduler;
      final status = await endpoint.dispatch('status', '');
      const requestId = '00000000-0000-4000-8000-000000000002';
      final payload = jsonEncode({
        'scheduleId': id,
        'epoch': status['epoch'],
        'requestId': requestId,
      });
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenThrow(failure);
      final first = await endpoint.dispatch('execute', payload);
      expect(first['uncertain'], isTrue);
      expect(await endpoint.dispatch('execute', payload), first);
      expect(errors, [same(failure)]);
      expect(
        messages.single,
        contains('command=execute scheduleId=$id requestId=$requestId'),
      );
      verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .called(1);
    },
  );

  test(
    'stopping observation releases UI while late receipt remains reusable',
    () async {
      final pending = Completer<rd.Result<void>>();
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenAnswer((_) => pending.future);
      final work = ui.executeNow(id);
      await Future<void>.delayed(Duration.zero);
      ui.stop();
      expect(
        (await work.timeout(const Duration(seconds: 1))).isError(),
        isTrue,
      );
      expect(ui.isExecutingBackup, isFalse);
      pending.complete(const rd.Success(rd.unit));
      await Future<void>.delayed(Duration.zero);
      expect((await ui.executeNow(id)).isSuccess(), isTrue);
      verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .called(1);
    },
  );

  test(
    'reachable service that is still starting does not receive execute',
    () async {
      final commands = <String>[];
      final proxy = ServiceSchedulerProxy((command, _) async {
        commands.add(command);
        return {'ok': false, 'code': 'service_not_ready'};
      });
      final result = await proxy.executeNow(id);
      expect(
        (result.exceptionOrNull()! as BackupFailure).code,
        'service_not_ready',
      );
      expect(commands, ['status']);
    },
  );

  test('partial write retry preserves the request identity', () async {
    final requests = <String>[];
    final proxy = ServiceSchedulerProxy((command, payload) async {
      if (command == 'status') return {'ok': true, 'epoch': 'same-service'};
      requests.add(payload);
      throw StateError('IPC request write failed or incomplete');
    });
    final first = await proxy.executeNow(id);
    expect(
      (first.exceptionOrNull()! as BackupFailure).code,
      'service_execution_unconfirmed',
    );
    await proxy.executeNow(id);
    expect(requests, hasLength(2));
    expect(requests[1], requests[0]);
  });

  test('write timeout retry preserves the request identity', () async {
    final requests = <String>[];
    final proxy = ServiceSchedulerProxy((command, payload) async {
      if (command == 'status') return {'ok': true, 'epoch': 'same-service'};
      requests.add(payload);
      throw TimeoutException('write deadline');
    });
    final first = await proxy.executeNow(id);
    expect(
      (first.exceptionOrNull()! as BackupFailure).code,
      'service_execution_unconfirmed',
    );
    await proxy.executeNow(id);
    expect(requests, hasLength(2));
    expect(requests[1], requests[0]);
  });

  test(
    'receipt limit refuses new work without evicting replay protection',
    () async {
      final endpoint = AdminSchedulerEndpoint(maxReceipts: 1)
        ..scheduler = scheduler;
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenAnswer((_) async => const rd.Success(rd.unit));
      final status = await endpoint.dispatch('status', '');
      String payload(String requestId, [String schedule = id]) => jsonEncode({
        'scheduleId': schedule,
        'requestId': requestId,
        'epoch': status['epoch'],
      });
      const a = '00000000-0000-4000-8000-000000000002';
      const b = '00000000-0000-4000-8000-000000000003';
      expect((await endpoint.dispatch('execute', payload(a)))['ok'], isTrue);
      expect((await endpoint.dispatch('execute', payload(b)))['ok'], isFalse);
      expect(
        (await endpoint.dispatch('execute', payload(a, b)))['ok'],
        isFalse,
      );
      expect((await endpoint.dispatch('execute', payload(a)))['ok'], isTrue);
      verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .called(1);
    },
  );

  test(
    'lost reply followed by retry returns receipt without another backup',
    () async {
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenAnswer((_) async => const rd.Success(rd.unit));
      var loseReply = true;
      final proxy = ServiceSchedulerProxy((command, payload) async {
        final result = await ipc.schedulerRequest(command, payload);
        if (command == 'execute' && loseReply) {
          loseReply = false;
          throw TimeoutException('reply lost after completion');
        }
        return result;
      });
      expect((await proxy.executeNow(id)).isError(), isTrue);
      expect((await proxy.executeNow(id)).isSuccess(), isTrue);
      verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .called(1);
    },
  );

  test(
    'retry after service restart cannot execute under a new epoch',
    () async {
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenAnswer((_) async => const rd.Success(rd.unit));
      var loseReply = true;
      final proxy = ServiceSchedulerProxy((command, payload) async {
        final result = await ipc.schedulerRequest(command, payload);
        if (command == 'execute' && loseReply) {
          loseReply = false;
          throw TimeoutException('lost');
        }
        return result;
      });
      await proxy.executeNow(id);
      await ipc.stop();
      await ipc.startServer(role: 'service');
      // Retry while the restarted service is still initializing must not erase
      // the old attempt and permit a fresh command after it becomes ready.
      expect((await proxy.executeNow(id)).isError(), isTrue);
      ipc.scheduler = scheduler;
      expect((await proxy.executeNow(id)).isError(), isTrue);
      expect((await proxy.executeNow(id)).isError(), isTrue);
      verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .called(1);
    },
  );

  test(
    'restart between status and execute rejects the delayed command',
    () async {
      final proxy = ServiceSchedulerProxy((command, payload) async {
        if (command == 'execute') {
          await ipc.stop();
          await ipc.startServer(role: 'service');
          ipc.scheduler = scheduler;
        }
        return ipc.schedulerRequest(command, payload);
      });
      expect((await proxy.executeNow(id)).isError(), isTrue);
      verifyNever(
        () => scheduler.executeNow(any(), runId: any(named: 'runId')),
      );
    },
  );

  test(
    'two connections replaying one request share the same running backup',
    () async {
      final done = Completer<rd.Result<void>>();
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenAnswer((_) => done.future);
      final status = await ipc.schedulerRequest('status');
      final payload = jsonEncode({
        'scheduleId': id,
        'epoch': status['epoch'],
        'requestId': '00000000-0000-4000-8000-000000000002',
      });
      final a = ipc.schedulerRequest('execute', payload);
      final b = ipc.schedulerRequest('execute', payload);
      await Future<void>.delayed(Duration.zero);
      done.complete(const rd.Success(rd.unit));
      expect((await a)['ok'], isTrue);
      expect((await b)['ok'], isTrue);
      verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .called(1);
    },
  );

  test(
    'cancel targets the identified run and not another session backup',
    () async {
      final done = Completer<rd.Result<void>>();
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenAnswer((_) => done.future);
      when(() => scheduler.cancelRun(id, any()))
          .thenAnswer((_) async => const rd.Success(rd.unit));
      final work = ui.executeNow(id);
      await Future<void>.delayed(Duration.zero);
      expect((await ui.cancelExecution(id)).isSuccess(), isTrue);
      verify(() => scheduler.cancelRun(id, any())).called(1);
      verifyNever(() => scheduler.cancelExecution(id));
      final otherSession = ServiceSchedulerProxy(ipc.schedulerRequest);
      expect((await otherSession.cancelExecution(id)).isError(), isTrue);
      done.complete(const rd.Success(rd.unit));
      await work;
      expect((await ui.cancelExecution(id)).isError(), isTrue);
    },
  );

  test(
    'new service has no stale scheduler handler before startup completes',
    () async {
      await ipc.stop();
      await ipc.startServer(role: 'service');
      expect((await ui.executeNow(id)).isError(), isTrue);
      verifyNever(
        () => scheduler.executeNow(any(), runId: any(named: 'runId')),
      );
    },
  );

  test(
    'shutdown during handshake never sends a late execute command',
    () async {
      final handshake = Completer<Map<String, dynamic>>();
      final commands = <String>[];
      final proxy = ServiceSchedulerProxy((command, payload) async {
        commands.add(command);
        return handshake.future;
      });
      final result = proxy.executeNow(id);
      proxy.suspendExecutions();
      handshake.complete({'ok': true, 'epoch': 'ready'});
      expect((await result).isError(), isTrue);
      expect(commands, ['status']);
    },
  );

  test('installed or uncertain service uses admin even when stopped', () {
    expect(
      ExecutionOwnership.useAdministrativeUi(
        scheduledLaunch: false,
        serviceInstalled: true,
        statusUnknown: false,
      ),
      isTrue,
    );
    expect(
      ExecutionOwnership.useAdministrativeUi(
        scheduledLaunch: false,
        serviceInstalled: false,
        statusUnknown: true,
      ),
      isTrue,
    );
    expect(
      ExecutionOwnership.useAdministrativeUi(
        scheduledLaunch: true,
        serviceInstalled: true,
        statusUnknown: false,
      ),
      isFalse,
    );
    expect(
      ExecutionOwnership.useAdministrativeUi(
        scheduledLaunch: false,
        serviceInstalled: false,
        statusUnknown: false,
      ),
      isFalse,
    );
  });

  test('Terminal Server sessions have isolated UI pipes and locks', () {
    expect(
      SingleInstanceConfig.administrativeMutex(1),
      isNot(SingleInstanceConfig.instanceMutexName),
    );
    expect(
      SingleInstanceConfig.administrativeMutex(1),
      isNot(SingleInstanceConfig.administrativeMutex(2)),
    );
    expect(
      SingleInstanceConfig.administrativePipe(1),
      isNot(SingleInstanceConfig.administrativePipe(2)),
    );
    expect(
      SingleInstanceConfig.administrativePipe(1),
      isNot(SingleInstanceConfig.ipcPipeName),
    );
  });

  test(
    'manual execution runs on executor and preserves failure details',
    () async {
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenAnswer(
            (_) async => const rd.Failure(
              BackupFailure(message: 'FTP: conexão interrompida'),
            ),
          );
      final result = await ui.executeNow(id);
      expect(result.isError(), isTrue);
      expect(failureUserMessage(result.exceptionOrNull()), contains('FTP'));
      verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .called(1);
    },
  );

  test(
    'two sessions reach same executor, which rejects concurrent work',
    () async {
      final pending = Completer<rd.Result<void>>();
      var calls = 0;
      when(
        () => scheduler.executeNow(id, runId: any(named: 'runId')),
      ).thenAnswer((_) {
        calls++;
        return calls == 1
            ? pending.future
            : Future.value(
                const rd.Failure(BackupFailure(message: 'Backup em execução')),
              );
      });
      final first = ui.executeNow(id);
      await Future<void>.delayed(Duration.zero);
      final otherSession = ServiceSchedulerProxy(ipc.schedulerRequest);
      expect((await otherSession.executeNow(id)).isError(), isTrue);
      pending.complete(const rd.Success(rd.unit));
      expect((await first).isSuccess(), isTrue);
      expect(calls, 2);
    },
  );

  test('double click only delegates once', () async {
    final pending = Completer<rd.Result<void>>();
    when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
        .thenAnswer((_) => pending.future);
    final first = ui.executeNow(id);
    expect((await ui.executeNow(id)).isError(), isTrue);
    pending.complete(const rd.Success(rd.unit));
    await first;
    verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
        .called(1);
  });

  test(
    'closing UI never stops or cancels service, late completion survives',
    () async {
      final pending = Completer<rd.Result<void>>();
      when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
          .thenAnswer((_) => pending.future);
      final work = ui.executeNow(id);
      await Future<void>.delayed(Duration.zero);
      ui.suspendExecutions();
      ui.stop();
      expect(await ui.waitForRunningBackups(), isTrue);
      verifyNever(scheduler.stop);
      verifyNever(scheduler.suspendExecutions);
      verifyNever(() => scheduler.cancelExecution(any()));
      expect(
        (await work.timeout(const Duration(seconds: 1))).isError(),
        isTrue,
      );
      pending.complete(const rd.Success(rd.unit));
      expect((await ui.executeNow(id)).isError(), isTrue);
    },
  );

  test('service stops: no fallback and no automatic retry', () async {
    await ipc.stop();
    expect((await ui.executeNow(id)).isError(), isTrue);
    verifyNever(() => scheduler.executeNow(any(), runId: any(named: 'runId')));
    await ui.start();
    expect(ui.isRunning, isFalse);
    expect(await ui.isServiceIdle(), isFalse);
  });

  test('handshake timeout reports no execution and does not retry', () async {
    var requests = 0;
    final proxy = ServiceSchedulerProxy((_, _) async {
      requests++;
      throw TimeoutException('lost reply');
    });
    final result = await proxy.executeNow(id);
    expect(result.isError(), isTrue);
    expect(
      failureUserMessage(result.exceptionOrNull()),
      contains('Nenhum backup foi solicitado'),
    );
    expect(requests, 1);
    expect(proxy.isExecutingBackup, isFalse);
    expect(proxy.activeScheduleId, isNull);
  });

  test(
    'failed connection before execute allows a fresh service epoch',
    () async {
      final commands = <String>[];
      final payloads = <Map<String, dynamic>>[];
      var epoch = 'old';
      final proxy = ServiceSchedulerProxy((command, payload) async {
        commands.add(command);
        if (command == 'status') return {'ok': true, 'epoch': epoch};
        payloads.add(jsonDecode(payload) as Map<String, dynamic>);
        if (epoch == 'old') throw const ServiceConnectionException();
        return {'ok': true};
      });
      final failed = await proxy.executeNow(id);
      expect(
        failureUserMessage(failed.exceptionOrNull()),
        contains('Nenhum backup foi solicitado'),
      );
      epoch = 'new';
      expect((await proxy.executeNow(id)).isSuccess(), isTrue);
      expect(commands, ['status', 'execute', 'status', 'execute']);
      expect(payloads.last['epoch'], 'new');
      expect(payloads.last['requestId'], isNot(payloads.first['requestId']));
    },
  );

  test('unavailable retry preserves an earlier ambiguous execution', () async {
    final payloads = <String>[];
    var handshakes = 0;
    final proxy = ServiceSchedulerProxy((command, payload) async {
      if (command == 'status') {
        handshakes++;
        return {'ok': true, 'epoch': 'original'};
      }
      payloads.add(payload);
      if (payloads.length == 1) throw TimeoutException('reply lost');
      if (payloads.length == 2) throw const ServiceConnectionException();
      return {'ok': true};
    });
    expect((await proxy.executeNow(id)).isError(), isTrue);
    final disconnected = await proxy.executeNow(id);
    expect(
      failureUserMessage(disconnected.exceptionOrNull()),
      contains('pode continuar'),
    );
    expect((await proxy.executeNow(id)).isSuccess(), isTrue);
    expect(handshakes, 1);
    expect(payloads.toSet(), hasLength(1));
  });

  test('stopped service can recover without reopening the interface', () async {
    await ipc.stop();
    final failed = await ui.executeNow(id);
    expect(
      failureUserMessage(failed.exceptionOrNull()),
      contains('Nenhum backup foi solicitado'),
    );
    await ipc.startServer(role: 'service');
    ipc.scheduler = scheduler;
    when(() => scheduler.executeNow(id, runId: any(named: 'runId')))
        .thenAnswer((_) async => const rd.Success(rd.unit));
    expect((await ui.executeNow(id)).isSuccess(), isTrue);
    verify(() => scheduler.executeNow(id, runId: any(named: 'runId')))
        .called(1);
  });

  test('cancel and refresh are delegated explicitly', () async {
    when(() => scheduler.cancelExecution(id))
        .thenAnswer((_) async => const rd.Success(rd.unit));
    when(() => scheduler.refreshSchedule(id))
        .thenAnswer((_) async => const rd.Success(rd.unit));
    expect((await ui.cancelExecution(id)).isError(), isTrue);
    expect((await ui.refreshSchedule(id)).isSuccess(), isTrue);
    verifyNever(() => scheduler.cancelExecution(id));
    verify(() => scheduler.refreshSchedule(id)).called(1);
  });

  test('invalid commands and IDs do not reach executor', () async {
    expect((await ipc.schedulerRequest('execute', 'bad'))['ok'], isFalse);
    expect((await ipc.schedulerRequest('stop', id))['ok'], isFalse);
    verifyNever(() => scheduler.executeNow(any(), runId: any(named: 'runId')));
  });

  test('administrative pipe rejects execution commands', () async {
    ipc.scheduler = null;
    expect((await ui.executeNow(id)).isError(), isTrue);
    verifyNever(() => scheduler.executeNow(any(), runId: any(named: 'runId')));
  });
}
