import 'package:backup_database/core/config/process_role.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/service_mode_detector.dart';

enum LaunchOrigin {
  manual,
  windowsStartup,
  serviceControlManager,
  scheduledExecution,
  unknown,
}

class LaunchBootstrapContext {
  const LaunchBootstrapContext({
    required this.launchOrigin,
    required this.isServiceMode,
    required this.processRole,
    required this.rawArgs,
    required this.rawEnvironment,
    required this.startMinimizedFromArgs,
    required this.usesLegacyWindowsStartupAlias,
  });

  final LaunchOrigin launchOrigin;
  final bool isServiceMode;
  final ProcessRole processRole;
  final List<String> rawArgs;
  final Map<String, String> rawEnvironment;
  final bool startMinimizedFromArgs;

  final bool usesLegacyWindowsStartupAlias;
}

class LaunchBootstrapContextResolver {
  const LaunchBootstrapContextResolver._();

  static LaunchBootstrapContext resolve({
    required List<String> rawArgs,
    required Map<String, String> rawEnvironment,
    bool? isServiceModeOverride,
  }) {
    final isServiceMode = isServiceModeOverride ??
        ServiceModeDetector.isServiceMode(executableArguments: rawArgs);

    final launchOrigin = isServiceMode
        ? LaunchOrigin.serviceControlManager
        : _launchOriginForUi(rawArgs);

    final startMinimizedFromArgs = rawArgs.contains(
      SingleInstanceConfig.minimizedArgument,
    );

    final processRole = isServiceMode ? ProcessRole.service : ProcessRole.ui;

    final usesLegacyWindowsStartupAlias =
        rawArgs.contains(SingleInstanceConfig.startupLaunchArgument);

    return LaunchBootstrapContext(
      launchOrigin: launchOrigin,
      isServiceMode: isServiceMode,
      processRole: processRole,
      rawArgs: List<String>.unmodifiable(List<String>.from(rawArgs)),
      rawEnvironment: Map<String, String>.unmodifiable(
        Map<String, String>.from(rawEnvironment),
      ),
      startMinimizedFromArgs: startMinimizedFromArgs,
      usesLegacyWindowsStartupAlias: usesLegacyWindowsStartupAlias,
    );
  }

  static LaunchOrigin _launchOriginForUi(List<String> rawArgs) {
    for (final arg in rawArgs) {
      if (arg.startsWith(SingleInstanceConfig.launchOriginArgumentPrefix)) {
        final value = arg
            .substring(SingleInstanceConfig.launchOriginArgumentPrefix.length)
            .trim();
        if (value == SingleInstanceConfig.windowsStartupLaunchOriginValue) {
          return LaunchOrigin.windowsStartup;
        }
        return LaunchOrigin.unknown;
      }
    }

    if (rawArgs.contains(SingleInstanceConfig.startupLaunchArgument)) {
      return LaunchOrigin.windowsStartup;
    }

    if (_hasScheduleIdArg(rawArgs)) {
      return LaunchOrigin.scheduledExecution;
    }

    return LaunchOrigin.manual;
  }

  static bool _hasScheduleIdArg(List<String> rawArgs) {
    const prefix = '--schedule-id=';
    for (final arg in rawArgs) {
      if (arg.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }
}
