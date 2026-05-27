import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';
import 'package:backup_database/presentation/boot/ipc_server_startup_task.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void _ignoreLog(String _) {}

void _ignoreLogWithError(
  String _, [
  Object? ignoredError,
  StackTrace? ignoredStackTrace,
]) {}

BootstrapConfig _config({bool singleInstanceEnabled = true}) {
  return BootstrapConfig(
    appMode: AppMode.server,
    singleInstanceEnabled: singleInstanceEnabled,
    uiSingleInstanceLockFallbackMode: SingleInstanceLockFallbackMode.failSafe,
    uiSchedulerFallbackMode: UiSchedulerFallbackMode.failOpen,
  );
}

IpcServerStartupTask _buildTask({
  required bool windowEnabled,
  required List<String> events,
  bool throwOnStart = false,
  BootstrapLog? logInfo,
  BootstrapLogWithError? logWarning,
  BootstrapLogWithError? logError,
}) {
  return IpcServerStartupTask(
    isWindowManagementEnabled: () => windowEnabled,
    showWindow: () async {
      events.add('show');
    },
    runSchedule: (id) async {
      events.add('run:$id');
      return 0;
    },
    startIpcServer: ({required onShowWindow, required onRunSchedule}) async {
      events.add('start_ipc');
      if (throwOnStart) {
        throw StateError('ipc boom');
      }
      await onShowWindow();
      await onRunSchedule('schedule-1');
    },
    logInfo: logInfo ?? _ignoreLog,
    logWarning: logWarning ?? _ignoreLogWithError,
    logError: logError ?? _ignoreLogWithError,
  );
}

void main() {
  group('IpcServerStartupTask.start', () {
    test('does not start when single instance disabled', () async {
      final events = <String>[];
      final infoLogs = <String>[];

      await _buildTask(
        windowEnabled: true,
        events: events,
        logInfo: infoLogs.add,
      ).start(_config(singleInstanceEnabled: false));

      expect(events, isEmpty);
      expect(infoLogs.first, contains('IPC Server nao iniciado'));
    });

    test('starts ipc server and bridges show window callback', () async {
      final events = <String>[];

      await _buildTask(windowEnabled: true, events: events).start(_config());

      expect(events, equals(['start_ipc', 'show', 'run:schedule-1']));
    });

    test('skips show window when window management disabled', () async {
      final events = <String>[];

      await _buildTask(windowEnabled: false, events: events).start(_config());

      expect(events, equals(['start_ipc', 'run:schedule-1']));
    });

    test('logs warning and swallows start failure', () async {
      final events = <String>[];
      final warnings = <String>[];

      await _buildTask(
        windowEnabled: true,
        events: events,
        throwOnStart: true,
        logWarning: (message, [_, _]) => warnings.add(message),
      ).start(_config());

      expect(events, equals(['start_ipc']));
      expect(warnings.first, contains('Erro ao inicializar IPC Server'));
    });
  });
}
