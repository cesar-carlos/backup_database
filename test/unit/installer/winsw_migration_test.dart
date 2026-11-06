import 'dart:io';

import 'package:backup_database/core/exit_codes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    'service-custom-account',
    'ui-running',
    'ui-stopped',
    'account-changed',
    'missing-account',
    'missing-wrapper',
    'start-fails',
  ]) {
    test('WinSW update restore: $scenario', () async {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        File('test/scripts/winsw_update_test.ps1').absolute.path,
        '-Scenario',
        scenario,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }, skip: !Platform.isWindows);
  }
  test('WinSW intentional stops do not trigger SCM recovery', () {
    for (final code in [77, 78]) {
      expect(ServiceModeExitCode.forWrapper(code, wrapper: 'winsw'), 0);
      expect(ServiceModeExitCode.forWrapper(code, wrapper: 'nssm'), code);
    }
    expect(ServiceModeExitCode.forWrapper(1, wrapper: 'winsw'), 1);
  });
  for (final scenario in [
    'running',
    'stopped',
    'custom-account',
    'custom-recovery',
    'fresh',
    'bad-hash',
    'unsupported',
    'image-fails',
    'start-fails',
    'stop-fails',
    'interrupted',
    'interrupted-bad-hash',
    'interrupted-missing-app',
    'commit-fails',
    'foreign-image',
    'account-changed-on-stop',
  ]) {
    test('WinSW migration: $scenario', () async {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        File('test/scripts/winsw_migration_test.ps1').absolute.path,
        '-Scenario',
        scenario,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }, skip: !Platform.isWindows);
  }
}
