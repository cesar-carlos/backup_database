import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/presentation/providers/system_settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SystemSettingsProvider', () {
    test('should register startup command with startup argument', () async {
      SharedPreferences.setMockInitialValues({
        'minimize_to_tray': true,
        'close_to_tray': true,
        'start_minimized': false,
        'start_with_windows': true,
      });

      final runner = _ProcessRunnerFake();
      final provider = SystemSettingsProvider(
        processRunner: runner.run,
        executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
      );

      await provider.initialize();

      expect(runner.calls.length, equals(1));
      final call = runner.calls.first;
      expect(call.executable, equals('reg'));
      expect(call.arguments, contains('add'));
      final command = _extractRegistryCommand(call.arguments);
      expect(
        command,
        equals(
          r'"C:\Apps\BackupDatabase.exe" '
          '${SingleInstanceConfig.startupLaunchArgument}',
        ),
      );
    });

    test(
      'should register startup command with minimized and startup arguments',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
          'start_minimized': true,
          'start_with_windows': true,
        });

        final runner = _ProcessRunnerFake();
        final provider = SystemSettingsProvider(
          processRunner: runner.run,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
        );

        await provider.initialize();

        expect(runner.calls.length, equals(1));
        final command = _extractRegistryCommand(runner.calls.first.arguments);
        expect(
          command,
          equals(
            r'"C:\Apps\BackupDatabase.exe" '
            '${SingleInstanceConfig.minimizedArgument} '
            '${SingleInstanceConfig.startupLaunchArgument}',
          ),
        );
      },
    );

    test(
      'should delete startup registry value when disabling startup',
      () async {
        SharedPreferences.setMockInitialValues({
          'minimize_to_tray': true,
          'close_to_tray': true,
          'start_minimized': false,
          'start_with_windows': false,
        });

        final runner = _ProcessRunnerFake();
        final provider = SystemSettingsProvider(
          processRunner: runner.run,
          executablePathProvider: () => r'C:\Apps\BackupDatabase.exe',
        );
        await provider.initialize();
        runner.clear();

        await provider.setStartWithWindows(false);

        expect(runner.calls.length, equals(1));
        final call = runner.calls.first;
        expect(call.executable, equals('reg'));
        expect(call.arguments, contains('delete'));
        expect(
          call.arguments,
          contains(r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'),
        );
        expect(call.arguments, contains('BackupDatabase'));
      },
    );
  });
}

String _extractRegistryCommand(List<String> args) {
  final commandIndex = args.indexOf('/d');
  return args[commandIndex + 1];
}

class _ProcessRunnerFake {
  final List<_CommandCall> calls = [];

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add(_CommandCall(executable: executable, arguments: arguments));
    return ProcessResult(1, 0, '', '');
  }

  void clear() {
    calls.clear();
  }
}

class _CommandCall {
  _CommandCall({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}
