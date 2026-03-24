import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
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
    });

    test(
      'should register machine startup with startup argument (client mode)',
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
          appModeProvider: () => AppMode.client,
        );

        await provider.initialize();

        expect(startup.calls.length, equals(1));
        final call = startup.calls.first;
        expect(call.enabled, isTrue);
        expect(call.installScheduledTask, isTrue);
        expect(call.executablePath, r'C:\Apps\BackupDatabase.exe');
        expect(
          call.taskArguments,
          SingleInstanceConfig.startupLaunchArgument,
        );
      },
    );

    test(
      'should register minimized and startup arguments when enabled',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });

        final startup = _FakeWindowsMachineStartupService();
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

        expect(startup.calls.length, equals(1));
        expect(
          startup.calls.first.taskArguments,
          equals(
            '${SingleInstanceConfig.minimizedArgument} '
            '${SingleInstanceConfig.startupLaunchArgument}',
          ),
        );
      },
    );

    test(
      'should not install scheduled task in server mode when startup enabled',
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

        expect(startup.calls.length, equals(1));
        expect(startup.calls.first.installScheduledTask, isFalse);
        expect(startup.calls.first.enabled, isTrue);
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
        expect(startup.calls.first.taskArguments, contains('--startup-launch'));
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
  Future<String?> getCustomTempDownloadsPath() async =>
      customTempDownloadsPath;

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
  });

  final List<_ApplyCall> calls = [];
  final WindowsMachineStartupOutcome outcome;

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
