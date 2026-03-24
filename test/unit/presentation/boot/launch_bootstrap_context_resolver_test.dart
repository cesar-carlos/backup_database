import 'package:backup_database/core/config/process_role.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/presentation/boot/launch_bootstrap_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LaunchBootstrapContextResolver', () {
    test(
      'should return windowsStartup when args contain launch-origin windows-startup',
      () {
        final ctx = LaunchBootstrapContextResolver.resolve(
              rawArgs: <String>[
                '--foo',
                SingleInstanceConfig.windowsStartupLaunchOriginArgument,
              ],
              rawEnvironment: const <String, String>{},
              isServiceModeOverride: false,
            );

        expect(ctx.launchOrigin, LaunchOrigin.windowsStartup);
        expect(ctx.isServiceMode, isFalse);
        expect(ctx.processRole, ProcessRole.ui);
        expect(ctx.usesLegacyWindowsStartupAlias, isFalse);
      },
    );

    test(
      'should return windowsStartup when args contain legacy --startup-launch',
      () {
        final ctx = LaunchBootstrapContextResolver.resolve(
              rawArgs: <String>[SingleInstanceConfig.startupLaunchArgument],
              rawEnvironment: const <String, String>{},
              isServiceModeOverride: false,
            );

        expect(ctx.launchOrigin, LaunchOrigin.windowsStartup);
        expect(ctx.usesLegacyWindowsStartupAlias, isTrue);
      },
    );

    test('should return manual when no startup marker is present', () {
      final ctx = LaunchBootstrapContextResolver.resolve(
        rawArgs: const <String>['--mode=client'],
        rawEnvironment: const <String, String>{},
        isServiceModeOverride: false,
      );

      expect(ctx.launchOrigin, LaunchOrigin.manual);
      expect(ctx.usesLegacyWindowsStartupAlias, isFalse);
    });

    test(
      'should return serviceControlManager when service mode is detected',
      () {
        final ctx = LaunchBootstrapContextResolver.resolve(
              rawArgs: <String>[
                SingleInstanceConfig.windowsStartupLaunchOriginArgument,
              ],
              rawEnvironment: const <String, String>{},
              isServiceModeOverride: true,
            );

        expect(ctx.launchOrigin, LaunchOrigin.serviceControlManager);
        expect(ctx.isServiceMode, isTrue);
        expect(ctx.processRole, ProcessRole.service);
        expect(ctx.usesLegacyWindowsStartupAlias, isFalse);
      },
    );

    test('should set startMinimizedFromArgs when args contain --minimized', () {
      final ctx = LaunchBootstrapContextResolver.resolve(
        rawArgs: const <String>[
          SingleInstanceConfig.minimizedArgument,
        ],
        rawEnvironment: const <String, String>{},
        isServiceModeOverride: false,
      );

      expect(ctx.startMinimizedFromArgs, isTrue);
    });

    test(
      'should return scheduledExecution when args contain --schedule-id=',
      () {
        final ctx = LaunchBootstrapContextResolver.resolve(
              rawArgs: const <String>['--schedule-id=job-1'],
              rawEnvironment: const <String, String>{},
              isServiceModeOverride: false,
            );

        expect(ctx.launchOrigin, LaunchOrigin.scheduledExecution);
      },
    );

    test(
      'should prefer explicit launch-origin over scheduled id when both present',
      () {
        final ctx = LaunchBootstrapContextResolver.resolve(
              rawArgs: <String>[
                '--schedule-id=job-1',
                SingleInstanceConfig.windowsStartupLaunchOriginArgument,
              ],
              rawEnvironment: const <String, String>{},
              isServiceModeOverride: false,
            );

        expect(ctx.launchOrigin, LaunchOrigin.windowsStartup);
      },
    );

    test('should return unknown for unrecognized launch-origin value', () {
      final ctx = LaunchBootstrapContextResolver.resolve(
        rawArgs: const <String>['--launch-origin=other'],
        rawEnvironment: const <String, String>{},
        isServiceModeOverride: false,
      );

      expect(ctx.launchOrigin, LaunchOrigin.unknown);
    });
  });
}
