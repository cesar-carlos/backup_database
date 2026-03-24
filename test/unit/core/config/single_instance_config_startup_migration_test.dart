import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SingleInstanceConfig.machineStartupArgsNeedProtocolMigration', () {
    test('should need migration for empty arguments', () {
      expect(
        SingleInstanceConfig.machineStartupArgsNeedProtocolMigration(''),
        isTrue,
      );
      expect(
        SingleInstanceConfig.machineStartupArgsNeedProtocolMigration('   '),
        isTrue,
      );
    });

    test('should need migration when legacy alias is present', () {
      expect(
        SingleInstanceConfig.machineStartupArgsNeedProtocolMigration(
          '--minimized ${SingleInstanceConfig.startupLaunchArgument}',
        ),
        isTrue,
      );
    });

    test('should need migration when launch-origin is missing', () {
      expect(
        SingleInstanceConfig.machineStartupArgsNeedProtocolMigration(
          SingleInstanceConfig.minimizedArgument,
        ),
        isTrue,
      );
    });

    test('should not need migration for canonical windows-startup args', () {
      expect(
        SingleInstanceConfig.machineStartupArgsNeedProtocolMigration(
          SingleInstanceConfig.windowsStartupLaunchOriginArgument,
        ),
        isFalse,
      );
      expect(
        SingleInstanceConfig.machineStartupArgsNeedProtocolMigration(
          '${SingleInstanceConfig.minimizedArgument} '
          '${SingleInstanceConfig.windowsStartupLaunchOriginArgument}',
        ),
        isFalse,
      );
    });
  });
}
