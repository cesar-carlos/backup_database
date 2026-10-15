import 'package:backup_database/core/config/process_role.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/schedule_args.dart';
import 'package:backup_database/core/utils/service_mode_detector.dart';
import 'package:flutter/foundation.dart';

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
    final detectedServiceMode =
        isServiceModeOverride ??
        ServiceModeDetector.isServiceMode(executableArguments: rawArgs);
    final isServiceMode = isServiceModeForLaunch(
      detectedServiceMode: detectedServiceMode,
      rawArgs: rawArgs,
    );

    final launchOrigin = isServiceMode
        ? LaunchOrigin.serviceControlManager
        : _launchOriginForUi(rawArgs);

    final startMinimizedFromArgs = rawArgs.contains(
      SingleInstanceConfig.minimizedArgument,
    );

    final processRole = isServiceMode ? ProcessRole.service : ProcessRole.ui;

    final usesLegacyWindowsStartupAlias = rawArgs.contains(
      SingleInstanceConfig.startupLaunchArgument,
    );

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

  /// A `--schedule-id` launch is a backup delegation, including when
  /// session 0 made the detector report service mode.
  @visibleForTesting
  static bool isServiceModeForLaunch({
    required bool detectedServiceMode,
    required List<String> rawArgs,
  }) {
    if (ScheduleArgs.contains(rawArgs)) {
      return false;
    }
    return detectedServiceMode;
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

    if (ScheduleArgs.contains(rawArgs)) {
      return LaunchOrigin.scheduledExecution;
    }

    return LaunchOrigin.manual;
  }
}
