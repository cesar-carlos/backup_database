import 'dart:async';
import 'dart:convert';

import 'package:backup_database/application/providers/backup_progress_provider.dart';
import 'package:backup_database/application/services/service_scheduler_proxy.dart';
import 'package:backup_database/domain/entities/backup_progress_snapshot.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/admin_scheduler_endpoint.dart';
import 'package:backup_database/infrastructure/external/system/ipc/in_memory_ipc_transport.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _Scheduler extends Mock
    implements ISchedulerService, IScopedBackupProgress {}

const _id = '00000000-0000-4000-8000-000000000001';
const _requestId = '00000000-0000-4000-8000-000000000002';
const _interval = Duration(milliseconds: 10);

void main() {
  test('stopping during handshake prevents dispatch and polling', () async {
    final handshake = Completer<Map<String, dynamic>>();
    final commands = <String>[];
    final proxy = ServiceSchedulerProxy((command, payload) {
      commands.add(command);
      return handshake.future;
    });
    final work = proxy.executeNow(_id);
    proxy.stop();
    handshake.complete({'ok': true, 'epoch': 'e', 'progressVersion': 1});
    expect((await work).isError(), isTrue);
    expect(commands, ['status']);
  });

  test(
    'confirmed restart ends waiting and late execute success cannot win',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var executions = 0;
      final provider = BackupProgressProvider()..startBackup('A');
      final proxy = ServiceSchedulerProxy(
        (command, payload) async {
          if (command == 'status') {
            return {'ok': true, 'epoch': 'old', 'progressVersion': 1};
          }
          final identity = jsonDecode(payload) as Map<String, dynamic>;
          if (command == 'execute') {
            executions++;
            if (executions == 1) return pending.future;
            expect(identity['epoch'], 'old');
            return {'ok': false, 'uncertain': true, 'error': 'restarted'};
          }
          return {
            ...identity,
            'ok': false,
            'code': 'service_restarted',
            'epoch': 'new',
          };
        },
        progressNotifier: provider,
        progressInterval: _interval,
      );
      addTearDown(proxy.stop);
      addTearDown(provider.dispose);
      final result = await proxy
          .executeNow(_id)
          .timeout(const Duration(seconds: 2));
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull().toString(), contains('reiniciou'));
      pending.complete({'ok': true});
      await Future<void>.delayed(_interval * 2);
      expect(provider.currentProgress!.step, isNot(BackupStep.completed));
      expect((await proxy.executeNow(_id)).isError(), isTrue);
      expect(executions, 2);
    },
  );

  test(
    'timed out poll recovers and its delayed reply cannot overwrite newer data',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final delayed = Completer<Map<String, dynamic>>();
      final recovered = Completer<void>();
      var polls = 0;
      late Map<String, dynamic> identity;
      final provider = BackupProgressProvider()..startBackup('A');
      final proxy = ServiceSchedulerProxy(
        (command, payload) async {
          if (command == 'status') {
            return {'ok': true, 'epoch': 'e', 'progressVersion': 1};
          }
          if (command == 'execute') return pending.future;
          identity = jsonDecode(payload) as Map<String, dynamic>;
          polls++;
          if (polls == 1) return delayed.future;
          if (!recovered.isCompleted) recovered.complete();
          return {
            ...identity,
            'ok': true,
            'progress': {
              'step': 'Compactando',
              'message': 'Current',
              'value': 0.7,
            },
          };
        },
        progressNotifier: provider,
        progressInterval: _interval,
        progressTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(proxy.stop);
      addTearDown(provider.dispose);
      final work = proxy.executeNow(_id);
      await recovered.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(provider.currentProgress!.progress, 0.7);
      delayed.complete({
        ...identity,
        'ok': true,
        'progress': {
          'step': 'Executando backup',
          'message': 'Stale',
          'value': 0.2,
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(provider.currentProgress!.message, 'Current');
      pending.complete({'ok': true});
      await work;
    },
  );

  test(
    'missing snapshot clears previous percentage without completing backup',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final polled = Completer<void>();
      final provider = BackupProgressProvider()..startBackup('A');
      provider.updateProgress(
        step: 'Compactando',
        message: 'Old',
        progress: 0.6,
      );
      final proxy = ServiceSchedulerProxy(
        (command, payload) async {
          if (command == 'status') {
            return {'ok': true, 'epoch': 'e', 'progressVersion': 1};
          }
          if (command == 'execute') return pending.future;
          if (!polled.isCompleted) polled.complete();
          return {
            ...jsonDecode(payload) as Map<String, dynamic>,
            'ok': true,
            'progress': null,
            'completed': true,
          };
        },
        progressNotifier: provider,
        progressInterval: _interval,
      );
      addTearDown(proxy.stop);
      addTearDown(provider.dispose);
      final work = proxy.executeNow(_id);
      await polled.future;
      await Future<void>.delayed(Duration.zero);
      expect(provider.currentProgress!.progress, isNull);
      expect(provider.isRunning, isTrue);
      expect(provider.currentProgress!.message, contains('confirmação'));
      pending.complete({'ok': true});
      await work;
    },
  );

  test(
    'IPC reports scoped stages while execute is pending, without new work',
    () async {
      final scheduler = _Scheduler();
      final pending = Completer<rd.Result<void>>();
      final entered = Completer<void>();
      String? runId;
      var snapshot = const BackupProgressSnapshot(
        step: 'Executando backup',
        message: 'Banco',
        progress: 0.2,
      );
      when(() => scheduler.isExecutingBackup).thenReturn(true);
      when(() => scheduler.executeNow(_id, runId: any(named: 'runId')))
          .thenAnswer((call) {
            runId = call.namedArguments[#runId] as String;
            entered.complete();
            return pending.future;
          });
      when(() => scheduler.progressForRun(any(), any())).thenAnswer((call) {
        expect(call.positionalArguments, [_id, runId]);
        return snapshot;
      });
      final ipc = IpcService(transport: InMemoryIpcTransport())
        ..scheduler = scheduler;
      await ipc.startServer(role: 'service');
      final provider = BackupProgressProvider()..startBackup('Test');
      final proxy = ServiceSchedulerProxy(
        ipc.schedulerRequest,
        progressNotifier: provider,
        progressInterval: _interval,
      );
      addTearDown(() async {
        proxy.stop();
        provider.dispose();
        await ipc.stop();
      });
      final work = proxy.executeNow(_id);
      await entered.future;
      Future<void> waitFor(double value) async {
        for (var i = 0; i < 100; i++) {
          if (provider.currentProgress!.progress == value) return;
          await Future<void>.delayed(_interval);
        }
        fail('Progress did not reach $value');
      }

      await waitFor(0.2);
      expect(provider.currentProgress!.step, BackupStep.executingBackup);
      snapshot = const BackupProgressSnapshot(
        step: 'Compactando',
        message: 'Compactação',
        progress: 0.6,
      );
      await waitFor(0.6);
      expect(provider.currentProgress!.step, BackupStep.compressing);
      snapshot = const BackupProgressSnapshot(
        step: 'Enviando para FTP',
        message: 'FTP 50%',
        progress: 0.9,
      );
      await waitFor(0.9);
      expect(provider.currentProgress!.step, BackupStep.uploading);
      expect(provider.currentProgress!.message, 'FTP 50%');
      pending.complete(const rd.Success(rd.unit));
      expect((await work).isSuccess(), isTrue);
      verify(() => scheduler.executeNow(_id, runId: any(named: 'runId')))
          .called(1);
    },
  );

  test(
    'endpoint rejects unknown, mismatched and previous epoch identities',
    () async {
      final scheduler = _Scheduler();
      when(() => scheduler.isExecutingBackup).thenReturn(true);
      final pending = Completer<rd.Result<void>>();
      when(() => scheduler.executeNow(_id, runId: _requestId))
          .thenAnswer((_) => pending.future);
      final endpoint = AdminSchedulerEndpoint()..scheduler = scheduler;
      final status = await endpoint.dispatch('status', '');
      final args = {
        'scheduleId': _id,
        'requestId': _requestId,
        'epoch': status['epoch'],
      };
      final payload = jsonEncode(args);
      expect((await endpoint.dispatch('progress', payload))['ok'], isFalse);
      final work = endpoint.dispatch('execute', payload);
      expect(
        (await endpoint.dispatch(
          'progress',
          jsonEncode({...args, 'scheduleId': _requestId}),
        ))['ok'],
        isFalse,
      );
      endpoint.newGeneration();
      expect((await endpoint.dispatch('progress', payload))['ok'], isFalse);
      verifyNever(() => scheduler.progressForRun(any(), any()));
      pending.complete(const rd.Success(rd.unit));
      await work;
    },
  );

  for (final stop in [false, true]) {
    test(
      'late progress is ignored after ${stop ? 'UI stop' : 'completion'}',
      () async {
        final pending = Completer<Map<String, dynamic>>();
        final poll = Completer<Map<String, dynamic>>();
        final polled = Completer<void>();
        late Map<String, dynamic> identity;
        var polls = 0;
        final provider = BackupProgressProvider()..startBackup('A');
        final proxy = ServiceSchedulerProxy(
          (command, payload) async {
            if (command == 'status') {
              return {'ok': true, 'epoch': 'e', 'progressVersion': 1};
            }
            identity = jsonDecode(payload) as Map<String, dynamic>;
            if (command == 'execute') return pending.future;
            polls++;
            if (!polled.isCompleted) polled.complete();
            return poll.future;
          },
          progressNotifier: provider,
          progressInterval: _interval,
        );
        addTearDown(proxy.stop);
        addTearDown(provider.dispose);
        final work = proxy.executeNow(_id);
        await polled.future;
        await Future<void>.delayed(_interval * 3);
        expect(polls, 1, reason: 'Only one progress request in flight');
        if (stop) proxy.stop();
        pending.complete({'ok': true});
        await work;
        provider.completeBackup();
        provider.startBackup('B');
        poll.complete({
          'ok': true,
          ...identity,
          'progress': {
            'step': 'Compactando',
            'message': 'Late A',
            'value': 0.6,
          },
        });
        await Future<void>.delayed(_interval * 2);
        expect(provider.currentProgress!.message, contains('B'));
        expect(polls, 1);
      },
    );
  }

  test('communication failure clears stale percentage and recovers without execute retry', () async {
    final pending = Completer<Map<String, dynamic>>();
    var polls = 0;
    var executions = 0;
    final lost = Completer<void>();
    final recovered = Completer<void>();
    final provider = BackupProgressProvider()..startBackup('A');
    final proxy = ServiceSchedulerProxy(
      (command, payload) async {
        if (command == 'status') {
          return {'ok': true, 'epoch': 'e', 'progressVersion': 1};
        }
        if (command == 'execute') {
          executions++;
          return pending.future;
        }
        final identity = jsonDecode(payload) as Map<String, dynamic>;
        polls++;
        if (polls == 1) {
          lost.complete();
          throw TimeoutException('disconnected');
        }
        if (!recovered.isCompleted) recovered.complete();
        return {
          'ok': true,
          ...identity,
          'progress': {
            'step': 'Compactando',
            'message': 'Working',
            'value': 0.7,
          },
        };
      },
      progressNotifier: provider,
      progressInterval: const Duration(milliseconds: 30),
    );
    addTearDown(proxy.stop);
    addTearDown(provider.dispose);
    final work = proxy.executeNow(_id);
    await lost.future;
    await Future<void>.delayed(Duration.zero);
    expect(provider.isRunning, isTrue);
    expect(provider.currentProgress!.progress, isNull);
    expect(provider.currentProgress!.message, contains('comunicação'));
    await recovered.future;
    await Future<void>.delayed(Duration.zero);
    expect(provider.currentProgress!.progress, 0.7);
    expect(executions, 1);
    pending.complete({'ok': true});
    await work;
  });

  for (final changedField in ['epoch', 'requestId', 'scheduleId']) {
    test('ignores progress with a different $changedField', () async {
      final pending = Completer<Map<String, dynamic>>();
      final polled = Completer<void>();
      final provider = BackupProgressProvider()..startBackup('A');
      final proxy = ServiceSchedulerProxy(
        (command, payload) async {
          if (command == 'status') {
            return {'ok': true, 'epoch': 'e', 'progressVersion': 1};
          }
          if (command == 'execute') return pending.future;
          final identity = jsonDecode(payload) as Map<String, dynamic>;
          if (!polled.isCompleted) polled.complete();
          return {
            'ok': true,
            ...identity,
            changedField: 'other',
            'progress': {
              'step': 'Compactando',
              'message': 'Wrong run',
              'value': 0.8,
            },
          };
        },
        progressNotifier: provider,
        progressInterval: _interval,
      );
      addTearDown(proxy.stop);
      addTearDown(provider.dispose);
      final work = proxy.executeNow(_id);
      await polled.future;
      await Future<void>.delayed(Duration.zero);
      expect(provider.currentProgress!.progress, isNull);
      expect(provider.currentProgress!.message, isNot('Wrong run'));
      pending.complete({'ok': true});
      await work;
    });
  }

  for (final terminalStep in ['Concluído', 'Erro']) {
    test(
      'progress $terminalStep cannot complete or release the UI slot',
      () async {
        final pending = Completer<Map<String, dynamic>>();
        final polled = Completer<void>();
        final provider = BackupProgressProvider()..startBackup('A');
        final proxy = ServiceSchedulerProxy(
          (command, payload) async {
            if (command == 'status') {
              return {'ok': true, 'epoch': 'e', 'progressVersion': 1};
            }
            if (command == 'execute') return pending.future;
            final identity = jsonDecode(payload) as Map<String, dynamic>;
            if (!polled.isCompleted) polled.complete();
            return {
              'ok': true,
              ...identity,
              'progress': {
                'step': terminalStep,
                'message': 'Terminal event',
                'value': 1,
              },
            };
          },
          progressNotifier: provider,
          progressInterval: _interval,
        );
        addTearDown(proxy.stop);
        addTearDown(provider.dispose);
        final work = proxy.executeNow(_id);
        await polled.future;
        await Future<void>.delayed(Duration.zero);
        expect(provider.isRunning, isTrue);
        expect(provider.currentProgress!.step, BackupStep.initializing);
        expect(provider.tryStartBackup('B'), isFalse);
        pending.complete({'ok': true});
        await work;
      },
    );
  }

  test(
    'legacy service keeps indeterminate progress without unsupported polling',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final provider = BackupProgressProvider()..startBackup('A');
      final commands = <String>[];
      final proxy = ServiceSchedulerProxy(
        (command, payload) async {
          commands.add(command);
          if (command == 'status') return {'ok': true, 'epoch': 'old'};
          return pending.future;
        },
        progressNotifier: provider,
        progressInterval: _interval,
      );
      addTearDown(proxy.stop);
      addTearDown(provider.dispose);
      final work = proxy.executeNow(_id);
      await Future<void>.delayed(_interval * 3);
      expect(commands, ['status', 'execute']);
      pending.complete({'ok': true});
      await work;
    },
  );
}
