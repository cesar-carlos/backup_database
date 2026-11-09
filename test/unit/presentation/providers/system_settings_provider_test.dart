import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/compatibility/feature_availability_snapshot.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/utils/pending_preference_operations.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:backup_database/domain/services/i_windows_machine_startup_service.dart';
import 'package:backup_database/infrastructure/repositories/user_preferences_repository.dart';
import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:backup_database/presentation/providers/system_settings_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/feature_availability_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SystemSettingsProvider', () {
    setUp(() async {
      if (Platform.isWindows) {
        await registerTestFeatureAvailability();
      }
    });
    tearDown(() async {
      if (Platform.isWindows) {
        await unregisterTestFeatureAvailability();
      }
    });

    test('failed rollback stays visible and blocks new startup changes until recovery', () async {
      SharedPreferences.setMockInitialValues({});
      final machine = _FakeMachineSettingsRepository()..failStartupWrite = true;
      var attempts = 0;
      var allowRecovery = false;
      final startup = _FakeWindowsMachineStartupService()
        ..applyResult = () async => WindowsMachineStartupOutcome(
          ok: ++attempts == 1 || allowRecovery,
          diagnostics: 'rollback denied',
        );
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: startup,
      );
      await provider.setStartWithWindows(true);
      expect(provider.hasStartupRecoveryError, isTrue);
      machine.failStartupWrite = false;
      await provider.setStartMinimized(true);
      expect(machine.startMinimized, isFalse);
      expect(provider.hasStartupRecoveryError, isTrue);
      expect(startup.calls.map((call) => call.enabled), [true, false, false]);
      allowRecovery = true;
      await provider.retryStartupRecovery();
      expect(provider.hasStartupRecoveryError, isFalse);
      await provider.setStartWithWindows(true);
      expect(machine.startWithWindows, isTrue);
      provider.dispose();
    });

    test(
      'rollback success after deadline cannot clear recovery state',
      () async {
        SharedPreferences.setMockInitialValues({});
        final entered = Completer<void>();
        final release = Completer<void>();
        var attempts = 0;
        final startup = _FakeWindowsMachineStartupService()
          ..beforeApply = () async {
            if (++attempts == 2) {
              entered.complete();
              await release.future;
            }
          };
        final provider = SystemSettingsProvider(
          machineSettingsRepository: _FakeMachineSettingsRepository()
            ..failStartupWrite = true,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
        );
        final change = provider.setStartWithWindows(true);
        await entered.future;
        expect(
          await PendingPreferenceOperations.drain(
            timeout: const Duration(milliseconds: 10),
          ),
          isFalse,
        );
        var notifications = 0;
        provider.addListener(() => notifications++);
        release.complete();
        await change;
        expect(provider.hasStartupRecoveryError, isTrue);
        expect(notifications, 0);
        provider.dispose();
      },
    );

    test(
      'late storage completion does not publish an expired preference',
      () async {
        SharedPreferences.setMockInitialValues({});
        final entered = Completer<void>();
        final release = Completer<void>();
        final machine = _FakeMachineSettingsRepository()
          ..beforeStartupWrite = () async {
            entered.complete();
            await release.future;
          };
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machine,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: _FakeWindowsMachineStartupService(),
        );
        final change = provider.setStartWithWindows(true);
        await entered.future;
        expect(
          await PendingPreferenceOperations.drain(
            timeout: const Duration(milliseconds: 10),
          ),
          isFalse,
        );
        var notifications = 0;
        provider.addListener(() => notifications++);
        release.complete();
        await change;
        expect(
          machine.startWithWindows,
          isTrue,
        ); // Already-issued write cannot be cancelled.
        expect(provider.startWithWindows, isFalse);
        expect(notifications, 0);
        provider.dispose();
      },
    );

    test('expired initial read does not start the next storage read', () async {
      SharedPreferences.setMockInitialValues({});
      final entered = Completer<void>();
      final release = Completer<void>();
      final machine = _FakeMachineSettingsRepository()
        ..readStartMinimized = () async {
          entered.complete();
          await release.future;
          return true;
        };
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: _FakeWindowsMachineStartupService(),
      );
      final boot = provider.initialize();
      await entered.future;
      expect(
        await PendingPreferenceOperations.drain(
          timeout: const Duration(milliseconds: 10),
        ),
        isFalse,
      );
      release.complete();
      await boot;
      expect(machine.startupReads, 0);
      expect(provider.startMinimized, isFalse);
      provider.dispose();
    });

    for (final expires in [false, true]) {
      test('active startup persistence with expired drain=$expires', () async {
        SharedPreferences.setMockInitialValues({});
        final entered = Completer<void>();
        final release = Completer<void>();
        final startup = _FakeWindowsMachineStartupService()
          ..beforeApply = () async {
            entered.complete();
            await release.future;
          };
        final machine = _FakeMachineSettingsRepository();
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machine,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
        );
        final change = provider.setStartWithWindows(true);
        await entered.future;
        provider.dispose();
        final draining = PendingPreferenceOperations.drain(
          timeout: expires
              ? const Duration(milliseconds: 10)
              : const Duration(seconds: 2),
        );
        if (expires) expect(await draining, isFalse);
        release.complete();
        await change;
        expect(await draining, !expires);
        expect(machine.startWithWindows, !expires);
      });
    }

    test(
      'dispose does not suppress compensation of an applied change',
      () async {
        SharedPreferences.setMockInitialValues({});
        final entered = Completer<void>();
        final release = Completer<void>();
        final startup = _FakeWindowsMachineStartupService()
          ..beforeApply = () async {
            if (!entered.isCompleted) {
              entered.complete();
              await release.future;
            }
          };
        final machine = _FakeMachineSettingsRepository()
          ..failStartupWrite = true;
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machine,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
        );
        final change = provider.setStartWithWindows(true);
        await entered.future;
        provider.dispose();
        release.complete();
        await change;
        expect(startup.calls.map((call) => call.enabled), [true, false]);
        expect(machine.startWithWindows, isFalse);
      },
    );

    test(
      'startup toggle before load preserves stored minimized argument',
      () async {
        SharedPreferences.setMockInitialValues({});
        final machine = _FakeMachineSettingsRepository(startMinimized: true);
        final startup = _FakeWindowsMachineStartupService();
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machine,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          appModeProvider: () => AppMode.client,
        );
        await provider.setStartWithWindows(true);
        expect(startup.calls.single.taskArguments, contains('--minimized'));
        expect(provider.startMinimized, isTrue);
        provider.dispose();
      },
    );

    test(
      'minimized toggle before load refreshes an already enabled task',
      () async {
        SharedPreferences.setMockInitialValues({});
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
          appModeProvider: () => AppMode.client,
        );
        await provider.setStartMinimized(true);
        expect(startup.calls.single.taskArguments, contains('--minimized'));
        expect(provider.startWithWindows, isTrue);
        provider.dispose();
      },
    );

    test('startup mutation waits for a successful initial read', () async {
      SharedPreferences.setMockInitialValues({});
      final machine = _FakeMachineSettingsRepository()
        ..readStartMinimized = () async => throw StateError('read failed');
      final startup = _FakeWindowsMachineStartupService();
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: startup,
      );
      await provider.setStartWithWindows(true);
      await provider.setStartMinimized(true);
      expect(startup.calls, isEmpty);
      expect(machine.startMinimized, isFalse);
      expect(machine.startWithWindows, isFalse);
      provider.dispose();
    });

    test(
      'saving compatibility fallbacks preserves stored preferences',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });
        await unregisterTestFeatureAvailability();
        service_locator.getIt.registerSingleton<FeatureAvailabilityService>(
          FeatureAvailabilityService(FeatureAvailabilitySnapshot.nonWindows()),
        );
        final machine = _FakeMachineSettingsRepository(startWithWindows: true);
        final prefs = UserPreferencesRepository();
        final startup = _FakeWindowsMachineStartupService();
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machine,
          userPreferencesRepository: prefs,
          windowsMachineStartupService: startup,
        );
        await provider.initialize();
        expect(provider.closeToTray, isFalse);
        expect(provider.startWithWindows, isFalse);
        await provider.saveSettings();
        expect(await prefs.getCloseToTray(), isTrue);
        expect(await prefs.getMinimizeToTray(), isTrue);
        expect(machine.startWithWindows, isTrue);
        expect(startup.inspectCalls, 0);
        provider.dispose();
      },
      skip: !Platform.isWindows,
    );

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

    test('concurrent boot and change finish with the new preference', () async {
      SharedPreferences.setMockInitialValues({});
      final entered = Completer<void>();
      final release = Completer<void>();
      final machine = _FakeMachineSettingsRepository()
        ..readStartMinimized = () async {
          entered.complete();
          await release.future;
          return false;
        };
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: _FakeWindowsMachineStartupService(),
      );
      final boot = provider.initialize();
      final duplicate = provider.initialize();
      await entered.future;
      final change = provider.setStartMinimized(true);
      release.complete();
      await Future.wait([boot, duplicate, change]);
      expect(machine.minimizedReads, 1);
      expect(provider.startMinimized, isTrue);
      expect(machine.startMinimized, isTrue);
      provider.dispose();
    });

    test('initialization can retry a failed read', () async {
      SharedPreferences.setMockInitialValues({});
      final machine = _FakeMachineSettingsRepository()
        ..readStartMinimized = () async => throw StateError('read failed');
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: _FakeWindowsMachineStartupService(),
      );
      await provider.initialize();
      machine.readStartMinimized = () async => true;
      await provider.initialize();
      expect(provider.startMinimized, isTrue);
      expect(machine.minimizedReads, 2);
      provider.dispose();
    });

    test('failed tray persistence keeps the previous close behavior', () async {
      SharedPreferences.setMockInitialValues({});
      final manager = WindowManagerService();
      final provider = SystemSettingsProvider(
        machineSettingsRepository: _FakeMachineSettingsRepository(),
        userPreferencesRepository: _FailingTrayPreferences(),
        windowsMachineStartupService: _FakeWindowsMachineStartupService(),
      );
      await provider.initialize();
      await provider.setCloseToTray(true);
      await provider.setMinimizeToTray(true);
      expect(provider.closeToTray, isFalse);
      expect(provider.minimizeToTray, isFalse);
      var exits = 0;
      manager.setCallbacks(onClose: () => exits++);
      await manager.onWindowClose();
      expect(exits, 1);
      manager.dispose();
      provider.dispose();
    });

    test('failed persistence rolls back the applied startup change', () async {
      SharedPreferences.setMockInitialValues({});
      final machine = _FakeMachineSettingsRepository()..failStartupWrite = true;
      final startup = _FakeWindowsMachineStartupService();
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: startup,
        appModeProvider: () => AppMode.client,
      );
      await provider.initialize();
      await provider.setStartWithWindows(true);
      expect(startup.calls.map((call) => call.enabled), [true, false]);
      expect(provider.startWithWindows, isFalse);
      expect(machine.startWithWindows, isFalse);
      machine.failStartupWrite = false;
      await provider.setStartWithWindows(true);
      expect(provider.startWithWindows, isTrue);
      provider.dispose();
    });

    test(
      'failed minimized persistence restores previous startup arguments',
      () async {
        SharedPreferences.setMockInitialValues({});
        final machine = _FakeMachineSettingsRepository(startWithWindows: true)
          ..failMinimizedWrite = true;
        final startup = _FakeWindowsMachineStartupService(
          inspection: const WindowsMachineStartupInspection(
            ok: true,
            hasLegacyRunEntry: false,
            hasScheduledTask: true,
          ),
        );
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machine,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          appModeProvider: () => AppMode.client,
        );
        await provider.initialize();
        await provider.setStartMinimized(true);
        expect(startup.calls, hasLength(2));
        expect(startup.calls.first.taskArguments, contains('--minimized'));
        expect(
          startup.calls.last.taskArguments,
          isNot(contains('--minimized')),
        );
        expect(provider.startMinimized, isFalse);
        provider.dispose();
      },
    );

    test('startup changes and minimized arguments execute in order', () async {
      SharedPreferences.setMockInitialValues({});
      final entered = Completer<void>();
      final release = Completer<void>();
      final startup = _FakeWindowsMachineStartupService()
        ..beforeApply = () async {
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          }
        };
      final machine = _FakeMachineSettingsRepository();
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: startup,
        appModeProvider: () => AppMode.client,
      );
      await provider.initialize();
      final enable = provider.setStartWithWindows(true);
      await entered.future;
      final minimize = provider.setStartMinimized(true);
      final disable = provider.setStartWithWindows(false);
      await Future<void>.delayed(Duration.zero);
      expect(startup.calls, hasLength(1));
      release.complete();
      await Future.wait([enable, minimize, disable]);
      expect(startup.calls.map((call) => call.enabled), [true, true, false]);
      expect(startup.calls[1].taskArguments, contains('--minimized'));
      expect(machine.startWithWindows, isFalse);
      expect(machine.startMinimized, isTrue);
      provider.dispose();
    });

    test('dispose during inspection prevents late startup migration', () async {
      SharedPreferences.setMockInitialValues({});
      final entered = Completer<void>();
      final release = Completer<void>();
      final startup =
          _FakeWindowsMachineStartupService(
              inspection: const WindowsMachineStartupInspection(
                ok: true,
                hasLegacyRunEntry: true,
                hasScheduledTask: false,
                needsStartupLaunchProtocolMigration: true,
              ),
            )
            ..beforeInspect = () async {
              entered.complete();
              await release.future;
            };
      final machine = _FakeMachineSettingsRepository(startWithWindows: true);
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: startup,
        appModeProvider: () => AppMode.client,
      );
      var notifications = 0;
      provider.addListener(() => notifications++);
      final boot = provider.initialize();
      await entered.future;
      final queued = provider.setStartWithWindows(false);
      provider.dispose();
      release.complete();
      await Future.wait([boot, queued]);
      expect(startup.calls, isEmpty);
      expect(machine.startWithWindows, isTrue);
      expect(notifications, 0);
    });

    test('failed legacy migration preserves enabled preference', () async {
      SharedPreferences.setMockInitialValues({});
      final machine = _FakeMachineSettingsRepository(startWithWindows: true);
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: _FakeWindowsMachineStartupService(
          outcome: const WindowsMachineStartupOutcome(
            ok: false,
            diagnostics: 'denied',
          ),
          inspection: const WindowsMachineStartupInspection(
            ok: true,
            hasLegacyRunEntry: true,
            hasScheduledTask: false,
            needsStartupLaunchProtocolMigration: true,
          ),
        ),
        appModeProvider: () => AppMode.client,
      );
      await provider.initialize();
      expect(provider.startWithWindows, isTrue);
      expect(machine.startWithWindows, isTrue);
      provider.dispose();
    });

    test(
      'save before initialization does not overwrite stored defaults',
      () async {
        SharedPreferences.setMockInitialValues({'close_to_tray': true});
        final machine = _FakeMachineSettingsRepository(startMinimized: true);
        final prefs = UserPreferencesRepository();
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machine,
          userPreferencesRepository: prefs,
          windowsMachineStartupService: _FakeWindowsMachineStartupService(),
        );
        await provider.saveSettings();
        expect(machine.startMinimized, isTrue);
        expect(await prefs.getCloseToTray(), isTrue);
        provider.dispose();
      },
    );

    test('shutdown blocks queued preference and startup changes', () async {
      SharedPreferences.setMockInitialValues({});
      final entered = Completer<void>();
      final release = Completer<void>();
      final machine = _FakeMachineSettingsRepository()
        ..readStartMinimized = () async {
          entered.complete();
          await release.future;
          return false;
        };
      final startup = _FakeWindowsMachineStartupService();
      final manager = WindowManagerService();
      final provider = SystemSettingsProvider(
        machineSettingsRepository: machine,
        userPreferencesRepository: UserPreferencesRepository(),
        windowsMachineStartupService: startup,
      );
      final boot = provider.initialize();
      await entered.future;
      final change = provider.setStartWithWindows(true);
      manager.beginShutdown();
      release.complete();
      await Future.wait([boot, change]);
      expect(startup.calls, isEmpty);
      expect(machine.startWithWindows, isFalse);
      provider.dispose();
      // Start a fresh window lifecycle so the singleton cannot leak into tests.
      const channel = MethodChannel('window_manager');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method.startsWith('is') ? false : null,
      );
      try {
        await manager.initialize(center: false);
      } finally {
        manager.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      }
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
        // §audit-2026-05-28: a task agora carrega --mode=client
        // explicito para nao depender de {app}\.install_mode.
        expect(
          call.taskArguments,
          '--mode=client --launch-origin=windows-startup',
        );
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
      'should reapply startup when only legacy HKCU Run exists and task is missing',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
        });

        final machineSettings = _FakeMachineSettingsRepository(
          startWithWindows: true,
        );
        final startup = _FakeWindowsMachineStartupService(
          inspection: const WindowsMachineStartupInspection(
            ok: true,
            hasLegacyRunEntry: true,
            hasScheduledTask: false,
            needsStartupLaunchProtocolMigration: true,
          ),
        );
        final provider = SystemSettingsProvider(
          machineSettingsRepository: machineSettings,
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.client,
        );

        await provider.initialize();

        expect(provider.startWithWindows, isTrue);
        expect(machineSettings.startWithWindows, isTrue);
        expect(startup.calls.length, equals(1));
        final call = startup.calls.first;
        expect(call.enabled, isTrue);
        expect(call.installScheduledTask, isTrue);
        // §audit-2026-05-28: --mode=client agora vai junto da task.
        expect(
          call.taskArguments,
          '--mode=client --launch-origin=windows-startup',
        );
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
      'should NOT inject --mode=client in unified mode',
      () async {
        // §audit-2026-05-28: o modo unified e legado mas continua valido
        // como fallback interno. Nao devemos injetar --mode=client nele.
        SharedPreferences.setMockInitialValues({});
        final startup = _FakeWindowsMachineStartupService();
        final provider = SystemSettingsProvider(
          machineSettingsRepository: _FakeMachineSettingsRepository(),
          userPreferencesRepository: UserPreferencesRepository(),
          windowsMachineStartupService: startup,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
          appModeProvider: () => AppMode.unified,
        );
        await provider.initialize();
        startup.calls.clear();

        await provider.setStartWithWindows(true);

        expect(startup.calls.length, equals(1));
        final call = startup.calls.first;
        expect(call.taskArguments, '--launch-origin=windows-startup');
        expect(call.taskArguments, isNot(contains('--mode=')));
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

class _FailingTrayPreferences extends UserPreferencesRepository {
  @override
  Future<void> setCloseToTray(bool value) async =>
      throw StateError('write failed');

  @override
  Future<void> setMinimizeToTray(bool value) async =>
      throw StateError('write failed');
}

class _FakeMachineSettingsRepository implements IMachineSettingsRepository {
  Future<void> Function()? beforeStartupWrite;
  int startupReads = 0;
  bool failStartupWrite = false;
  bool failMinimizedWrite = false;
  int minimizedReads = 0;
  Future<bool> Function()? readStartMinimized;
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
  Future<bool> getStartWithWindows() async {
    startupReads++;
    return startWithWindows;
  }

  @override
  Future<void> setStartWithWindows(bool value) async {
    await beforeStartupWrite?.call();
    if (failStartupWrite) throw StateError('storage failed');
    startWithWindows = value;
  }

  @override
  Future<bool> getStartMinimized() async {
    minimizedReads++;
    return readStartMinimized == null
        ? startMinimized
        : await readStartMinimized!();
  }

  @override
  Future<void> setStartMinimized(bool value) async {
    if (failMinimizedWrite) throw StateError('storage failed');
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

  String? pendingRemoteRunSnapshotJson;

  @override
  Future<String?> getPendingRemoteRunSnapshotJson() async =>
      pendingRemoteRunSnapshotJson;

  @override
  Future<void> setPendingRemoteRunSnapshotJson(String? json) async {
    pendingRemoteRunSnapshotJson = json;
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
  Future<WindowsMachineStartupOutcome> Function()? applyResult;
  Future<void> Function()? beforeApply;
  Future<void> Function()? beforeInspect;
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
    await beforeInspect?.call();
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
    await beforeApply?.call();
    return applyResult == null ? outcome : await applyResult!();
  }
}
