import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:backup_database/domain/services/i_windows_machine_startup_service.dart';
import 'package:backup_database/infrastructure/repositories/user_preferences_repository.dart';
import 'package:backup_database/presentation/providers/system_settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SystemSettingsProvider', () {
    test('should initialize first run with all toggles disabled', () async {
      SharedPreferences.setMockInitialValues({});

      final startup = _FakeWindowsMachineStartupService();
      final provider = SystemSettingsProvider(
        machineSettingsRepository: _FakeMachineSettingsRepository(),
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: startup,
        executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
      );

      await provider.initialize();

      expect(provider.minimizeToTray, isFalse);
      expect(provider.closeToTray, isFalse);
      expect(provider.startMinimized, isFalse);
      expect(provider.startWithWindows, isFalse);
      expect(startup.calls, isEmpty);
      expect(startup.inspectCalls, equals(0));
    });

    test(
      'should keep machine startup enabled when scheduled task exists (client mode)',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });

        final startup = _FakeWindowsMachineStartupService(
          inspection: const WindowsMachineStartupInspection(
            ok: true,
            hasLegacyRunEntry: false,
            hasScheduledTask: true,
          ),
        );
        final provider = SystemSettingsProvider(
          machineSettingsRepository: _FakeMachineSettingsRepository(
            startWithWindows: true,
          ),
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.client,
        );

        await provider.initialize();

        expect(provider.startWithWindows, isTrue);
        expect(startup.calls, isEmpty);
        expect(startup.inspectCalls, equals(1));
      },
    );

    test(
      'should keep startup enabled when scheduled task exists and start minimized is set',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });

        final startup = _FakeWindowsMachineStartupService(
          inspection: const WindowsMachineStartupInspection(
            ok: true,
            hasLegacyRunEntry: false,
            hasScheduledTask: true,
          ),
        );
        final provider = SystemSettingsProvider(
          machineSettingsRepository: _FakeMachineSettingsRepository(
            startWithWindows: true,
            startMinimized: true,
          ),
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.unified,
        );

        await provider.initialize();

        expect(provider.startWithWindows, isTrue);
        expect(provider.startMinimized, isTrue);
        expect(startup.calls, isEmpty);
        expect(startup.inspectCalls, equals(1));
      },
    );

    test(
      'should keep startup enabled in server mode without scheduled task',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });

        final startup = _FakeWindowsMachineStartupService();
        final provider = SystemSettingsProvider(
          machineSettingsRepository: _FakeMachineSettingsRepository(
            startWithWindows: true,
          ),
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.server,
        );

        await provider.initialize();

        expect(provider.startWithWindows, isTrue);
        expect(startup.calls, isEmpty);
        expect(startup.inspectCalls, equals(1));
      },
    );

    test(
      'should reapply machine startup on initialize when protocol migration is needed',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });

        final startup = _FakeWindowsMachineStartupService(
          inspection: const WindowsMachineStartupInspection(
            ok: true,
            hasLegacyRunEntry: true,
            hasScheduledTask: true,
            needsStartupLaunchProtocolMigration: true,
          ),
        );
        final provider = SystemSettingsProvider(
          machineSettingsRepository: _FakeMachineSettingsRepository(
            startWithWindows: true,
          ),
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.client,
        );

        await provider.initialize();

        expect(provider.startWithWindows, isTrue);
        expect(startup.calls.length, equals(1));
        final call = startup.calls.first;
        expect(call.enabled, isTrue);
        expect(call.installScheduledTask, isTrue);
        expect(call.taskArguments, '--launch-origin=windows-startup');
        expect(startup.inspectCalls, equals(1));
      },
    );

    test(
      'should not run startup migration reapply in server mode',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });

        final startup = _FakeWindowsMachineStartupService(
          inspection: const WindowsMachineStartupInspection(
            ok: true,
            hasLegacyRunEntry: true,
            hasScheduledTask: true,
            needsStartupLaunchProtocolMigration: true,
          ),
        );
        final provider = SystemSettingsProvider(
          machineSettingsRepository: _FakeMachineSettingsRepository(
            startWithWindows: true,
          ),
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.server,
        );

        await provider.initialize();

        expect(provider.startWithWindows, isTrue);
        expect(startup.calls, isEmpty);
        expect(startup.inspectCalls, equals(1));
      },
    );

    test(
      'should disable persisted startup on initialize when scheduled task is missing',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });

        final machineSettings = _FakeMachineSettingsRepository(
          startWithWindows: true,
        );
        final startup = _FakeWindowsMachineStartupService();
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machineSettings,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.client,
        );

        await provider.initialize();

        expect(provider.startWithWindows, isFalse);
        expect(machineSettings.startWithWindows, isFalse);
        expect(startup.calls, isEmpty);
        expect(startup.inspectCalls, equals(1));
      },
    );

    test(
      'should apply disabled startup when turning off',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });

        final startup = _FakeWindowsMachineStartupService();
        final provider = SystemSettingsProvider(
          machineSettingsRepository: _FakeMachineSettingsRepository(),
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.client,
        );
        await provider.initialize();
        startup.calls.clear();

        await provider.setStartWithWindows(false);

        expect(startup.calls.length, equals(1));
        final call = startup.calls.first;
        expect(call.enabled, isFalse);
        expect(call.installScheduledTask, isTrue);
        expect(call.taskArguments, isEmpty);
      },
    );

    test(
      'should not persist startup toggle when machine startup apply fails',
      () async {
        SharedPreferences.setMockInitialValues({});

        final startup = _FakeWindowsMachineStartupService(
          outcome: const WindowsMachineStartupOutcome(
            ok: false,
            diagnostics: 'schtasks failed',
          ),
          inspection: const WindowsMachineStartupInspection(
            ok: true,
            hasLegacyRunEntry: false,
            hasScheduledTask: true,
          ),
        );
        final machineSettings = _FakeMachineSettingsRepository();
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machineSettings,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.client,
        );

        await provider.initialize();
        await provider.setStartWithWindows(true);

        expect(provider.startWithWindows, isFalse);
        expect(machineSettings.startWithWindows, isFalse);
        expect(startup.calls.length, equals(1));
      },
    );

    test(
      'should not persist start minimized when startup task refresh fails',
      () async {
        SharedPreferences.setMockInitialValues({});

        final startup = _FakeWindowsMachineStartupService(
          outcome: const WindowsMachineStartupOutcome(
            ok: false,
            diagnostics: 'schtasks failed',
          ),
          inspection: const WindowsMachineStartupInspection(
            ok: true,
            hasLegacyRunEntry: false,
            hasScheduledTask: true,
          ),
        );
        final machineSettings = _FakeMachineSettingsRepository(
          startWithWindows: true,
        );
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machineSettings,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.client,
        );

        await provider.initialize();
        startup.calls.clear();

        await provider.setStartMinimized(true);

        expect(provider.startMinimized, isFalse);
        expect(machineSettings.startMinimized, isFalse);
        expect(startup.calls.length, equals(1));
        expect(
          startup.calls.first.taskArguments,
          contains('--launch-origin=windows-startup'),
        );
      },
    );
  });
}

class _FakeMachineSettingsRepository implements IMachineSettingsRepository {
  _FakeMachineSettingsRepository({
    this.startWithWindows = false,
    this.startMinimized = false,
  });

  bool startWithWindows;
  bool startMinimized;
  String? customTempDownloadsPath;
  String? receivedBackupsDefaultPath;
  String? scheduleTransferDestinationsJson;

  @override
  Future<bool> getStartWithWindows() async => startWithWindows;

  @override
  Future<void> setStartWithWindows(bool value) async {
    startWithWindows = value;
  }

  @override
  Future<bool> getStartMinimized() async => startMinimized;

  @override
  Future<void> setStartMinimized(bool value) async {
    startMinimized = value;
  }

  @override
  Future<String?> getCustomTempDownloadsPath() async => customTempDownloadsPath;

  @override
  Future<void> setCustomTempDownloadsPath(String? path) async {
    customTempDownloadsPath = path;
  }

  @override
  Future<String?> getReceivedBackupsDefaultPath() async =>
      receivedBackupsDefaultPath;

  @override
  Future<void> setReceivedBackupsDefaultPath(String? path) async {
    receivedBackupsDefaultPath = path;
  }

  @override
  Future<String?> getScheduleTransferDestinationsJson() async =>
      scheduleTransferDestinationsJson;

  @override
  Future<void> setScheduleTransferDestinationsJson(String? json) async {
    scheduleTransferDestinationsJson = json;
  }
}

class _ApplyCall {
  _ApplyCall({
    required this.enabled,
    required this.installScheduledTask,
    required this.executablePath,
    required this.taskArguments,
  });

  final bool enabled;
  final bool installScheduledTask;
  final String executablePath;
  final String taskArguments;
}

class _FakeWindowsMachineStartupService
    implements IWindowsMachineStartupService {
  _FakeWindowsMachineStartupService({
    this.outcome = const WindowsMachineStartupOutcome(ok: true),
    this.inspection = const WindowsMachineStartupInspection(
      ok: true,
      hasLegacyRunEntry: false,
      hasScheduledTask: false,
    ),
  });

  final List<_ApplyCall> calls = [];
  final WindowsMachineStartupOutcome outcome;
  final WindowsMachineStartupInspection inspection;
  int inspectCalls = 0;

  @override
  Future<WindowsMachineStartupInspection> inspect() async {
    inspectCalls += 1;
    return inspection;
  }

  @override
  Future<WindowsMachineStartupOutcome> apply({
    required bool enabled,
    required bool installScheduledTask,
    required String executablePath,
    required String taskArguments,
  }) async {
    calls.add(
      _ApplyCall(
        enabled: enabled,
        installScheduledTask: installScheduledTask,
        executablePath: executablePath,
        taskArguments: taskArguments,
      ),
    );
    return outcome;
  }
}
