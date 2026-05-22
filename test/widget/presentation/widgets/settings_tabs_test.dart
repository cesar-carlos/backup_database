import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/compatibility/feature_availability_snapshot.dart';
import 'package:backup_database/core/compatibility/feature_disable_reason.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/domain/services/i_windows_machine_startup_service.dart';
import 'package:backup_database/domain/services/i_windows_service_event_logger.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/presentation/pages/settings_page.dart';
import 'package:backup_database/presentation/providers/app_density_provider.dart';
import 'package:backup_database/presentation/providers/skeleton_loading_preference_provider.dart';
import 'package:backup_database/presentation/providers/system_settings_provider.dart';
import 'package:backup_database/presentation/providers/theme_provider.dart';
import 'package:backup_database/presentation/widgets/settings/general_settings_tab.dart';
import 'package:backup_database/presentation/widgets/settings/machine_storage_settings_section.dart';
import 'package:backup_database/presentation/widgets/settings/service_settings_tab.dart';
import 'package:backup_database/presentation/widgets/settings/system_settings_tab.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

import '../../../helpers/stub_temp_directory_service.dart';
import '../../../support/feature_availability_test_support.dart';

class _FakeUserPreferencesRepository implements IUserPreferencesRepository {
  @override
  Future<void> ensureTrayDefaults() async {}

  @override
  Future<bool> getCloseToTray() async => false;

  @override
  Future<bool> getDarkMode() async => false;

  @override
  Future<bool> getLocalScheduleTimerEnabled() async => true;

  @override
  Future<bool> getMinimizeToTray() async => false;

  @override
  Future<String?> getR1MultiProfileLegacyHintLastDismissedSignature() async =>
      null;

  @override
  Future<bool> getSkeletonLoadingEnabled() async => true;

  @override
  Future<String?> getUiDensity() async => null;

  @override
  Future<bool> getUseSystemAccentColor() async => false;

  @override
  Future<bool> getUseWindowsMicaBackdrop() async => false;

  @override
  Future<void> setCloseToTray(bool value) async {}

  @override
  Future<void> setDarkMode(bool value) async {}

  @override
  Future<void> setLocalScheduleTimerEnabled(bool value) async {}

  @override
  Future<void> setMinimizeToTray(bool value) async {}

  @override
  Future<void> setR1MultiProfileLegacyHintLastDismissedSignature(
    String signature,
  ) async {}

  @override
  Future<void> setSkeletonLoadingEnabled(bool value) async {}

  @override
  Future<void> setUiDensity(String name) async {}

  @override
  Future<void> setUseSystemAccentColor(bool value) async {}

  @override
  Future<void> setUseWindowsMicaBackdrop(bool value) async {}
}

class _FakeMachineSettingsRepository implements IMachineSettingsRepository {
  @override
  Future<String?> getCustomTempDownloadsPath() async => null;

  @override
  Future<String?> getReceivedBackupsDefaultPath() async => null;

  @override
  Future<String?> getScheduleTransferDestinationsJson() async => null;

  @override
  Future<bool> getStartMinimized() async => false;

  @override
  Future<bool> getStartWithWindows() async => false;

  @override
  Future<void> setCustomTempDownloadsPath(String? path) async {}

  @override
  Future<void> setReceivedBackupsDefaultPath(String? path) async {}

  @override
  Future<void> setScheduleTransferDestinationsJson(String? json) async {}

  @override
  Future<void> setStartMinimized(bool value) async {}

  @override
  Future<void> setStartWithWindows(bool value) async {}
}

class _FakeWindowsMachineStartupService
    implements IWindowsMachineStartupService {
  @override
  Future<WindowsMachineStartupOutcome> apply({
    required bool enabled,
    required bool installScheduledTask,
    required String executablePath,
    required String taskArguments,
  }) async {
    return const WindowsMachineStartupOutcome(ok: true);
  }

  @override
  Future<WindowsMachineStartupInspection> inspect() async {
    return const WindowsMachineStartupInspection(
      ok: true,
      hasLegacyRunEntry: false,
      hasScheduledTask: false,
    );
  }
}

class _FakeWindowsServiceService implements IWindowsServiceService {
  @override
  Future<rd.Result<WindowsServiceStatus>> getStatus() async {
    return const rd.Success(
      WindowsServiceStatus(
        isInstalled: true,
        isRunning: true,
        serviceName: 'BackupDatabaseService',
      ),
    );
  }

  @override
  Future<rd.Result<void>> installService({
    String? serviceUser,
    String? servicePassword,
  }) async => const rd.Success(unit);

  @override
  Future<rd.Result<void>> restartService() async => const rd.Success(unit);

  @override
  Future<rd.Result<void>> startService() async => const rd.Success(unit);

  @override
  Future<rd.Result<void>> stopService() async => const rd.Success(unit);

  @override
  Future<rd.Result<void>> uninstallService() async => const rd.Success(unit);
}

class _FakeWindowsServiceEventLogger implements IWindowsServiceEventLogger {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> logServiceStarted() async {}

  @override
  Future<void> logServiceStopped() async {}

  @override
  Future<void> logShutdownBackupsIncomplete({
    required Duration timeout,
    String? details,
  }) async {}

  @override
  Future<void> logCriticalError({
    required String error,
    String? context,
  }) async {}

  @override
  Future<void> logInstallFailed({required String error}) async {}

  @override
  Future<void> logInstallStarted() async {}

  @override
  Future<void> logInstallSucceeded() async {}

  @override
  Future<void> logStartFailed({required String error}) async {}

  @override
  Future<void> logStartStarted() async {}

  @override
  Future<void> logStartSucceeded() async {}

  @override
  Future<void> logStartTimeout({required Duration timeout}) async {}

  @override
  Future<void> logStopFailed({required String error}) async {}

  @override
  Future<void> logStopStarted() async {}

  @override
  Future<void> logStopSucceeded() async {}

  @override
  Future<void> logStopTimeout({required Duration timeout}) async {}

  @override
  Future<void> logUninstallFailed({required String error}) async {}

  @override
  Future<void> logUninstallStarted() async {}

  @override
  Future<void> logUninstallSucceeded() async {}
}

Future<void> _registerFeatureAvailability(
  FeatureAvailabilitySnapshot snapshot,
) async {
  if (getIt.isRegistered<FeatureAvailabilityService>()) {
    await getIt.unregister<FeatureAvailabilityService>();
  }
  getIt.registerSingleton<FeatureAvailabilityService>(
    FeatureAvailabilityService(snapshot),
  );
}

Future<void> _registerSettingsDependencies({
  FeatureAvailabilitySnapshot featureSnapshot =
      kTestFeatureAvailabilityAllEnabled,
}) async {
  await _registerFeatureAvailability(featureSnapshot);
  final prefs = _FakeUserPreferencesRepository();
  getIt.registerSingleton<IUserPreferencesRepository>(prefs);
  getIt.registerSingleton<TempDirectoryService>(StubTempDirectoryService());
  getIt.registerSingleton<ClipboardService>(ClipboardService());
}

Future<void> _cleanupSettingsDependencies() async {
  if (getIt.isRegistered<ClipboardService>()) {
    await getIt.unregister<ClipboardService>();
  }
  if (getIt.isRegistered<TempDirectoryService>()) {
    await getIt.unregister<TempDirectoryService>();
  }
  if (getIt.isRegistered<IUserPreferencesRepository>()) {
    await getIt.unregister<IUserPreferencesRepository>();
  }
  if (getIt.isRegistered<FeatureAvailabilityService>()) {
    await getIt.unregister<FeatureAvailabilityService>();
  }
}

Future<void> _pumpSettingsHarness(
  WidgetTester tester,
  Widget child, {
  bool wrapWithScaffold = true,
}) async {
  final prefs = getIt<IUserPreferencesRepository>();
  final themeProvider = ThemeProvider(userPreferencesRepository: prefs);
  final densityProvider = AppDensityProvider(userPreferencesRepository: prefs);
  final skeletonProvider = SkeletonLoadingPreferenceProvider(
    userPreferencesRepository: prefs,
  );
  final systemSettingsProvider = SystemSettingsProvider(
    machineSettingsRepository: _FakeMachineSettingsRepository(),
    userPreferencesRepository: prefs,
    windowsMachineStartupService: _FakeWindowsMachineStartupService(),
    appModeProvider: () => currentAppMode,
  );
  final autoUpdateProvider = AutoUpdateProvider(
    autoUpdateService: AutoUpdateService(),
  );
  final windowsServiceProvider = WindowsServiceProvider(
    _FakeWindowsServiceService(),
    _FakeWindowsServiceEventLogger(),
  );

  final home = wrapWithScaffold
      ? ScaffoldPage(content: SingleChildScrollView(child: child))
      : child;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: densityProvider),
        ChangeNotifierProvider.value(value: skeletonProvider),
        ChangeNotifierProvider.value(value: systemSettingsProvider),
        ChangeNotifierProvider.value(value: autoUpdateProvider),
        ChangeNotifierProvider.value(value: windowsServiceProvider),
      ],
      child: FluentApp(
        theme: AppTheme.lightFluentTheme,
        home: home,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    setAppMode(AppMode.client);
    await _registerSettingsDependencies();
  });

  tearDown(() async {
    await _cleanupSettingsDependencies();
    setAppMode(AppMode.unified);
  });

  testWidgets('SettingsPage renders four settings tabs including system', (
    WidgetTester tester,
  ) async {
    setAppMode(AppMode.unified);
    await _pumpSettingsHarness(
      tester,
      const SettingsPage(),
      wrapWithScaffold: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Windows service'), findsOneWidget);
    expect(find.text('Licensing'), findsOneWidget);

    final systemLeft = tester.getTopLeft(find.text('System')).dx;
    final updatesLeft = tester.getTopLeft(find.text('Updates')).dx;
    expect(systemLeft, lessThan(updatesLeft));
  });

  testWidgets(
    'GeneralSettingsTab renders updates first and keeps updater details collapsed',
    (
      WidgetTester tester,
    ) async {
      await _pumpSettingsHarness(tester, const GeneralSettingsTab());

      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('Updater technical details'), findsOneWidget);
      expect(find.text('Temporary downloads folder'), findsOneWidget);
      expect(find.byType(MachineStorageSettingsSection), findsOneWidget);

      final updatesTop = tester.getTopLeft(find.text('Updates')).dy;
      final downloadsTop = tester
          .getTopLeft(find.text('Temporary downloads folder'))
          .dy;
      expect(updatesTop, lessThan(downloadsTop));

      final expander = tester.widget<Expander>(find.byType(Expander).first);
      expect(expander.initiallyExpanded, isFalse);
    },
  );

  testWidgets('SystemSettingsTab renders appearance without updater section', (
    WidgetTester tester,
  ) async {
    await _pumpSettingsHarness(tester, const SystemSettingsTab());

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Dark theme'), findsOneWidget);
    expect(find.text('Updater technical details'), findsNothing);
  });

  testWidgets(
    'SystemSettingsTab shows inline compatibility message for disabled tray',
    (
      WidgetTester tester,
    ) async {
      await _cleanupSettingsDependencies();
      await _registerSettingsDependencies(
        featureSnapshot: const FeatureAvailabilitySnapshot(
          isWindows: true,
          majorVersion: 10,
          minorVersion: 0,
          isServerLikely: false,
          serverDetectionReliable: true,
          isInteractiveSessionLikely: false,
          interactiveDetectionReliable: true,
          osVersionParseFailed: false,
          webviewRuntimeAvailable: true,
          webviewProbeTimedOut: false,
          autoUpdateEnabled: true,
          windowManagementEnabled: true,
          trayEnabled: false,
          taskSchedulerEnabled: true,
          windowsServiceManagementEnabled: true,
          startupAtLogonTaskEnabled: true,
          externalBrowserOAuthEnabled: true,
          embeddedWebviewOAuthEnabled: true,
          trayDisabledReason:
              FeatureDisableReason.trayRequiresInteractiveSession,
        ),
      );

      await _pumpSettingsHarness(tester, const SystemSettingsTab());

      expect(
        find.text('System tray requires an interactive session (Desktop/RDP).'),
        findsNWidgets(2),
      );
    },
  );

  testWidgets(
    'ServiceSettingsTab prioritizes status, actions and collapsed diagnostics',
    (
      WidgetTester tester,
    ) async {
      await _pumpSettingsHarness(tester, const ServiceSettingsTab());
      await tester.pump();

      expect(find.text('Service status'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Restart'), findsOneWidget);
      expect(find.text('View detailed diagnostics'), findsOneWidget);
      final expanders = tester
          .widgetList<Expander>(find.byType(Expander))
          .toList();
      expect(expanders, isNotEmpty);
      expect(expanders.last.initiallyExpanded, isFalse);
    },
  );
}
