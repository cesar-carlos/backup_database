import 'package:backup_database/core/config/process_role.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/presentation/boot/app_initializer.dart';
import 'package:backup_database/presentation/boot/launch_bootstrap_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Settings extends Mock implements IMachineSettingsRepository {}

void main() {
  setUp(service_locator.getIt.pushNewScope);
  tearDown(service_locator.getIt.popScope);

  for (final origin in [LaunchOrigin.manual, LaunchOrigin.windowsStartup]) {
    for (final saved in [false, true]) {
      for (final explicit in [false, true]) {
        test(
          '$origin saved minimized=$saved explicit minimized=$explicit',
          () async {
            final settings = _Settings();
            when(settings.getStartMinimized).thenAnswer((_) async => saved);
            service_locator.getIt.registerSingleton<IMachineSettingsRepository>(
              settings,
            );
            final config = await AppInitializer.getLaunchConfig(
              bootstrapContext: LaunchBootstrapContext(
                launchOrigin: origin,
                isServiceMode: false,
                processRole: ProcessRole.ui,
                rawArgs: explicit ? ['--minimized'] : [],
                rawEnvironment: const {},
                startMinimizedFromArgs: explicit,
                usesLegacyWindowsStartupAlias: false,
              ),
            );
            expect(
              config.startMinimized,
              explicit || (origin == LaunchOrigin.windowsStartup && saved),
            );
          },
        );
      }
    }
  }
}
