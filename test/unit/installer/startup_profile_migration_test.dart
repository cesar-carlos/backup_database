import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'migrates loaded and offline Terminal Server profiles and old task',
    () async {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'test/scripts/migrate_startup_entries_test.ps1',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('Startup migration regression tests passed'),
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'installer runs migration before removing current user legacy entries',
    () {
      final setup = File('installer/setup.iss').readAsStringSync();
      expect(
        setup,
        contains('Source: "migrate_startup_entries.ps1"; Flags: dontcopy'),
      );
      final procedure = setup.substring(
        setup.lastIndexOf('procedure RemoveLegacyStartupEntries();'),
      );
      expect(
        procedure.indexOf("'migrate_startup_entries.ps1'"),
        lessThan(procedure.indexOf("Exec('reg.exe'")),
      );
    },
  );
}
