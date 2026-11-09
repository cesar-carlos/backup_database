import 'dart:async';

import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/utils/pending_preference_operations.dart';
import 'package:backup_database/domain/services/i_app_database_lifecycle.dart';
import 'package:backup_database/domain/services/i_backup_cancellation_service.dart';
import 'package:backup_database/domain/services/i_execution_queue_housekeeping_scheduler.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Scheduler extends Mock implements ISchedulerService {}

class _Database extends Mock implements IAppDatabaseLifecycle {}

class _Socket extends Mock implements SocketServerService {}

class _Instance extends Mock implements ISingleInstanceService {}

class _Updates extends Mock implements AutoUpdateService {}

class _Queue extends Mock implements IExecutionQueueHousekeepingScheduler {}

class _Cancellation extends Mock implements IBackupCancellationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const trayChannel = MethodChannel('tray_manager');
  late List<String> events;
  late _Database database;
  late _Socket socket;
  late _Scheduler scheduler;
  setUp(() {
    events = [];
    scheduler = _Scheduler();
    database = _Database();
    socket = _Socket();
    final instance = _Instance();
    final updates = _Updates();
    final queue = _Queue();
    final cancellation = _Cancellation();
    when(scheduler.suspendExecutions).thenAnswer((_) {
      events.add('suspend');
    });
    when(scheduler.stop).thenAnswer((_) {
      events.add('scheduler');
    });
    when(() => scheduler.waitForRunningBackups(timeout: any(named: 'timeout')))
        .thenAnswer((_) async {
          events.add('drain');
          return true;
        });
    when(updates.dispose).thenAnswer((_) async {
      events.add('updates');
    });
    when(socket.stop).thenAnswer((_) async {
      events.add('socket');
    });
    when(queue.stop).thenAnswer((_) {
      events.add('queue');
    });
    when(cancellation.cancelAllRunning).thenAnswer((_) {
      events.add('cancel');
    });
    when(database.close).thenAnswer((_) async {
      events.add('database');
    });
    when(instance.releaseLock).thenAnswer((_) async {
      events.add('lock');
    });
    getIt.registerSingleton<ISchedulerService>(scheduler);
    getIt.registerSingleton<IAppDatabaseLifecycle>(database);
    getIt.registerSingleton<SocketServerService>(socket);
    getIt.registerSingleton<ISingleInstanceService>(instance);
    getIt.registerSingleton<AutoUpdateService>(updates);
    getIt.registerSingleton<IExecutionQueueHousekeepingScheduler>(queue);
    getIt.registerSingleton<IBackupCancellationService>(cancellation);
    messenger.setMockMethodCallHandler(trayChannel, (call) async {
      events.add('tray:${call.method}');
      return null;
    });
  });
  setUpAll(() => registerFallbackValue(Duration.zero));
  tearDown(() async {
    await getIt.reset();
    messenger.setMockMethodCallHandler(trayChannel, null);
  });

  test(
    'stops producers and backups before DB and releases instance last',
    () async {
      await AppCleanup.cleanup();
      expect(events, [
        'suspend',
        'updates',
        'socket',
        'queue',
        'cancel',
        'scheduler',
        'drain',
        'database',
        'tray:destroy',
        'lock',
      ]);
    },
  );

  test('concurrent cleanup releases each resource only once', () async {
    final closing = Completer<void>();
    final entered = Completer<void>();
    when(database.close).thenAnswer((_) async {
      events.add('database');
      entered.complete();
      await closing.future;
    });
    final first = AppCleanup.cleanup();
    await entered.future;
    final second = AppCleanup.cleanup();
    expect(identical(first, second), isTrue);
    expect(events, isNot(contains('lock')));
    closing.complete();
    await Future.wait([first, second]);
    expect(events.where((e) => e == 'database').length, 1);
    expect(events.where((e) => e == 'lock').length, 1);
  });

  test('database waits for an active preference change', () async {
    final release = Completer<void>();
    final changing = PendingPreferenceOperations.run((operation) async {
      await release.future;
      expect(operation.isValid, isTrue);
      events.add('preference_saved');
    });
    final cleanup = AppCleanup.cleanup();
    await Future<void>.delayed(Duration.zero);
    expect(events, isNot(contains('database')));
    release.complete();
    await Future.wait([changing, cleanup]);
    expect(
      events.indexOf('preference_saved'),
      lessThan(events.indexOf('database')),
    );
  });

  test('timeout invalidates late writes before database close', () async {
    final release = Completer<void>();
    final changing = PendingPreferenceOperations.run((operation) async {
      await release.future;
      if (operation.isValid) events.add('late_write');
    });
    await AppCleanup.cleanup(stepTimeout: const Duration(milliseconds: 10));
    expect(events, contains('database'));
    expect(events, contains('lock'));
    release.complete();
    await changing;
    expect(events, isNot(contains('late_write')));
  });

  test(
    'throwing suspension and stalled socket do not strand the lock',
    () async {
      final pending = Completer<void>();
      when(scheduler.suspendExecutions).thenThrow(StateError('suspend failed'));
      when(socket.stop).thenAnswer((_) => pending.future);
      await AppCleanup.cleanup(stepTimeout: const Duration(milliseconds: 10));
      expect(
        events,
        containsAllInOrder([
          'queue',
          'cancel',
          'scheduler',
          'database',
          'tray:destroy',
          'lock',
        ]),
      );
      pending.complete();
    },
  );
}
