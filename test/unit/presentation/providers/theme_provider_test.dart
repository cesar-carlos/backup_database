import 'dart:async';

import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/providers/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_theme/system_theme.dart';

void main() {
  group('ThemeProvider', () {
    late _FakeUserPreferencesRepository prefs;
    late ThemeProvider provider;

    setUp(() {
      prefs = _FakeUserPreferencesRepository();
      provider = ThemeProvider(userPreferencesRepository: prefs);
    });

    tearDown(() => provider.dispose());

    test('concurrent initialization reads preferences once', () async {
      await Future.wait([provider.initialize(), provider.initialize()]);
      expect(prefs.darkReads, 1);
    });

    test('late initial read does not overwrite a newer theme choice', () async {
      final read = Completer<bool>();
      prefs.readDark = () => read.future;
      final boot = provider.initialize();
      final change = provider.setDarkMode(true);
      read.complete(false);
      await Future.wait([boot, change]);
      expect(provider.isDarkMode, isTrue);
      expect(prefs.darkMode, isTrue);
    });

    test('rapid theme changes persist in request order', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final writes = <bool>[];
      prefs.beforeWriteDark = (value) async {
        writes.add(value);
        if (value) {
          entered.complete();
          await release.future;
        }
      };
      final first = provider.setDarkMode(true);
      await entered.future;
      final last = provider.setDarkMode(false);
      await Future<void>.delayed(Duration.zero);
      expect(writes, [true]);
      release.complete();
      await Future.wait([first, last]);
      expect(prefs.darkMode, isFalse);
      expect(provider.isDarkMode, isFalse);
      expect(writes, [true, false]);
    });

    test('accent plugin failure preserves persisted dark preference', () async {
      provider.dispose();
      prefs.darkMode = true;
      prefs.useSystemAccentColor = true;
      provider = ThemeProvider(
        userPreferencesRepository: prefs,
        loadSystemAccentColor: () async =>
            throw StateError('plugin unavailable'),
        accentChanges: const Stream.empty(),
      );
      await provider.initialize();
      expect(provider.isDarkMode, isTrue);
      expect(provider.useSystemAccentColor, isTrue);
    });

    test(
      'dispose during accent load never attaches a late subscription',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final changes = StreamController<SystemAccentColor>.broadcast();
        final pending = ThemeProvider(
          userPreferencesRepository: prefs,
          loadSystemAccentColor: () async {
            entered.complete();
            await release.future;
          },
          accentChanges: changes.stream,
        );
        prefs.useSystemAccentColor = true;
        var notifications = 0;
        pending.addListener(() => notifications++);
        final boot = pending.initialize();
        await entered.future;
        pending.dispose();
        release.complete();
        await boot;
        expect(changes.hasListener, isFalse);
        expect(notifications, 0);
        await changes.close();
      },
    );

    test('failed preference read can be retried', () async {
      prefs.readDark = () async => throw StateError('temporarily unavailable');
      await provider.initialize();
      prefs.readDark = () async => true;
      await provider.initialize();
      expect(provider.isDarkMode, isTrue);
      expect(prefs.darkReads, 2);
    });

    test('initialize loads dark mode from repository', () async {
      prefs.darkMode = true;

      await provider.initialize();

      expect(provider.isDarkMode, isTrue);
    });

    test('initialize is idempotent', () async {
      prefs.darkMode = true;
      await provider.initialize();
      prefs.darkMode = false;

      await provider.initialize();

      expect(provider.isDarkMode, isTrue);
    });

    test('setDarkMode updates state and persists', () async {
      await provider.initialize();

      await provider.setDarkMode(true);

      expect(provider.isDarkMode, isTrue);
      expect(prefs.darkMode, isTrue);
    });

    test('toggleTheme flips mode', () async {
      await provider.initialize();
      expect(provider.isDarkMode, isFalse);

      await provider.toggleTheme();

      expect(provider.isDarkMode, isTrue);
      expect(prefs.darkMode, isTrue);
    });

    test('fluentAccentColor uses brand when system accent is off', () async {
      prefs.useSystemAccentColor = false;
      await provider.initialize();
      expect(
        identical(provider.fluentAccentColor, AppTheme.brandFluentAccent),
        isTrue,
      );
    });

    test('setUseSystemAccentColor persists', () async {
      await provider.initialize();
      await provider.setUseSystemAccentColor(true);
      expect(provider.useSystemAccentColor, isTrue);
      expect(prefs.useSystemAccentColor, isTrue);
    });
  });
}

class _FakeUserPreferencesRepository implements IUserPreferencesRepository {
  int darkReads = 0;
  Future<bool> Function()? readDark;
  Future<void> Function(bool)? beforeWriteDark;
  bool darkMode = false;
  bool minimizeToTray = false;
  bool closeToTray = false;
  String? r1Signature;
  bool useSystemAccentColor = false;
  bool useWindowsMicaBackdrop = true;

  @override
  Future<void> ensureTrayDefaults() async {}

  @override
  Future<bool> getCloseToTray() async => closeToTray;

  @override
  Future<bool> getDarkMode() async {
    darkReads++;
    return readDark == null ? darkMode : await readDark!();
  }

  @override
  Future<bool> getMinimizeToTray() async => minimizeToTray;

  @override
  Future<String?> getR1MultiProfileLegacyHintLastDismissedSignature() async =>
      r1Signature;

  @override
  Future<void> setCloseToTray(bool value) async {
    closeToTray = value;
  }

  @override
  Future<void> setDarkMode(bool value) async {
    await beforeWriteDark?.call(value);
    darkMode = value;
  }

  @override
  Future<bool> getUseSystemAccentColor() async => useSystemAccentColor;

  @override
  Future<bool> getUseWindowsMicaBackdrop() async => useWindowsMicaBackdrop;

  @override
  Future<void> setUseSystemAccentColor(bool value) async {
    useSystemAccentColor = value;
  }

  @override
  Future<void> setUseWindowsMicaBackdrop(bool value) async {
    useWindowsMicaBackdrop = value;
  }

  String? uiDensity;

  @override
  Future<String?> getUiDensity() async => uiDensity;

  @override
  Future<void> setUiDensity(String name) async {
    uiDensity = name;
  }

  bool skeletonLoadingEnabled = true;

  @override
  Future<bool> getSkeletonLoadingEnabled() async => skeletonLoadingEnabled;

  @override
  Future<void> setSkeletonLoadingEnabled(bool value) async {
    skeletonLoadingEnabled = value;
  }

  @override
  Future<void> setMinimizeToTray(bool value) async {
    minimizeToTray = value;
  }

  @override
  Future<void> setR1MultiProfileLegacyHintLastDismissedSignature(
    String signature,
  ) async {
    r1Signature = signature;
  }

  @override
  Future<bool> getLocalScheduleTimerEnabled() async => true;

  @override
  Future<void> setLocalScheduleTimerEnabled(bool value) async {}
}
