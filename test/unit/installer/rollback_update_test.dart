import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    'registration-nssm',
    'registration-winsw',
    'registration-account-changed',
    'registration-image-changed',
    'registration-missing',
    'registration-corrupt',
    'registration-foreign-new',
    'registration-missing-account',
    'partial-copy',
    'stopped',
    'before-copy',
    'committed',
    'corrupt',
    'copy-failure',
    'service-failure',
    'service-preflight-failure',
    'start-failure',
    'interrupted-swap',
    'absent-directory',
    'changed-before-arm',
    'snapshot-failure',
  ]) {
    test('persistent installer rollback: $scenario', () async {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        File('test/scripts/rollback_update_test.ps1').absolute.path,
        '-Scenario',
        scenario,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }, skip: !Platform.isWindows);
  }
}
