import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/domain/services/i_remote_staging_cleanup_scheduler.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/services/i_temporary_backup_cleanup_scheduler.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Scheduler extends Mock implements ISchedulerService {}

class _Remote extends Mock implements IRemoteStagingCleanupScheduler {}

class _Temporary extends Mock implements ITemporaryBackupCleanupScheduler {}

class _Connection extends Mock implements ConnectionManager {}

void main() {
  for (final running in [true, false]) {
    test(
      'failed install restores only previously active services ($running)',
      () async {
        final scheduler = _Scheduler();
        final remote = _Remote();
        final temporary = _Temporary();
        final connection = _Connection();
        var reconnected = false;
        when(() => scheduler.isRunning).thenReturn(running);
        when(scheduler.start).thenAnswer((_) async {});
        when(() => remote.isRunning).thenReturn(running);
        when(() => temporary.isRunning).thenReturn(running);
        when(connection.disconnect).thenAnswer((_) async {});
        when(connection.captureReconnectAction).thenReturn(
          running
              ? () async {
                  reconnected = true;
                }
              : null,
        );
        getIt.registerSingleton<ISchedulerService>(scheduler);
        getIt.registerSingleton<IRemoteStagingCleanupScheduler>(remote);
        getIt.registerSingleton<ITemporaryBackupCleanupScheduler>(temporary);
        getIt.registerSingleton<ConnectionManager>(connection);
        addTearDown(getIt.reset);
        await AppCleanup.prepareForInstall();
        verifyInOrder([
          scheduler.suspendExecutions,
          connection.disconnect,
          scheduler.stop,
        ]);
        await AppCleanup.recoverFailedInstall();
        verify(scheduler.resumeExecutions).called(1);
        if (running) {
          verify(scheduler.start).called(1);
          verify(remote.start).called(1);
          verify(temporary.start).called(1);
        } else {
          verifyNever(scheduler.start);
          verifyNever(remote.start);
          verifyNever(temporary.start);
        }
        expect(reconnected, running);
        await AppCleanup.recoverFailedInstall();
        verifyNever(scheduler.resumeExecutions);
      },
    );
  }
}
