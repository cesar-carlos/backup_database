import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BootstrapConfigResolver', () {
    test('resolves app mode and bootstrap flags from centralized inputs', () {
      final warnings = <String>[];
      final resolver = BootstrapConfigResolver(
        environment: const <String, String>{
          'APP_MODE': 'client',
          'SINGLE_INSTANCE_ENABLED': 'false',
          'SINGLE_INSTANCE_LOCK_FALLBACK_MODE': 'fail_open',
          'UI_SCHEDULER_FALLBACK_MODE': 'fail_safe',
        },
        onWarning: warnings.add,
      );

      final config = resolver.resolve(rawArgs: const <String>[]);

      expect(config.appMode, AppMode.client);
      expect(config.singleInstanceEnabled, isFalse);
      expect(
        config.uiSingleInstanceLockFallbackMode,
        SingleInstanceLockFallbackMode.failOpen,
      );
      expect(
        config.uiSchedulerFallbackMode,
        UiSchedulerFallbackMode.failSafe,
      );
      expect(warnings, isEmpty);
    });

    test('prefers CLI args over environment app mode', () {
      final resolver = BootstrapConfigResolver(
        environment: const <String, String>{'APP_MODE': 'server'},
      );

      final config = resolver.resolve(rawArgs: const <String>['--mode=client']);

      expect(config.appMode, AppMode.client);
    });

    test('ignores disabled single instance flag outside debug mode', () {
      final resolver = BootstrapConfigResolver(
        environment: const <String, String>{
          'SINGLE_INSTANCE_ENABLED': 'false',
        },
        isDebugMode: false,
      );

      final config = resolver.resolve(rawArgs: const <String>[]);

      expect(config.singleInstanceEnabled, isTrue);
    });

    test('defaults invalid UI scheduler fallback to failOpen and warns', () {
      final warnings = <String>[];
      final resolver = BootstrapConfigResolver(
        environment: const <String, String>{
          'UI_SCHEDULER_FALLBACK_MODE': 'failsafe',
        },
        onWarning: warnings.add,
      );

      final config = resolver.resolve(rawArgs: const <String>[]);

      expect(config.uiSchedulerFallbackMode, UiSchedulerFallbackMode.failOpen);
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('UI_SCHEDULER_FALLBACK_MODE'));
    });
  });
}
