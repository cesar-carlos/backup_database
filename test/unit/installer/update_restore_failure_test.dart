import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'setup_iss_parser.dart';

void main() {
  test(
    'recapture preserves original service state after failed attempt',
    () async {
      final temp = await Directory.systemTemp.createTemp('capture_retry_');
      addTearDown(() => temp.delete(recursive: true));
      final context = File(p.join(temp.path, 'context.json'));
      final original = jsonEncode({
        'schemaVersion': 2,
        'origin': 'service',
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'serviceExists': true,
        'serviceWasRunning': true,
        'serviceConfig': {
          'AppParameters': '--original',
          'ObjectName': 'LocalSystem',
        },
      });
      await context.writeAsString(original);
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        File('installer/capture_update_context.ps1').absolute.path,
        '-ContextPath',
        context.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(await context.readAsString(), original);
    },
    skip: !Platform.isWindows,
  );
  for (final origin in ['service', 'ui']) {
    for (final wasRunning in [false, true]) {
      test(
        'pre-install recovery decision origin=$origin running=$wasRunning',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'recovery_decision_',
          );
          addTearDown(() => temp.delete(recursive: true));
          final context = File(p.join(temp.path, 'context.json'));
          await context.writeAsString(
            jsonEncode({
              'schemaVersion': 2,
              'origin': origin,
              'serviceExists': true,
              'serviceWasRunning': wasRunning,
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
            }),
          );
          final wrapper = File(p.join(temp.path, 'run.ps1'));
          await wrapper.writeAsString(r'''
function global:Get-Service { param($Name, $ErrorAction) return [pscustomobject]@{Status='Stopped'} }
& $env:RECOVERY_SCRIPT -ContextPath "$PSScriptRoot\context.json"
exit $LASTEXITCODE
''');
          final result = await Process.run(
            'powershell.exe',
            ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', wrapper.path],
            environment: {
              'RECOVERY_SCRIPT': File(
                'installer/check_update_service_recovery.ps1',
              ).absolute.path,
            },
          );
          expect(
            result.exitCode,
            origin == 'service' || wasRunning ? 0 : 1,
            reason: result.stderr.toString(),
          );
        },
        skip: !Platform.isWindows,
      );
    }
  }
  test(
    'installer exposes restoration failure and limits abort recovery',
    () async {
      final iss = SetupIssParser.fromFile(File('installer/setup.iss'));
      expect(
        iss.routineContains(
          'GetCustomSetupExitCode',
          'OperationalRestoreFailed',
        ),
        isTrue,
      );
      expect(
        iss.routineContains(
          'CurStepChanged',
          'OperationalRestoreFailed := OperationalRestoreFailed or (RestoreExitCode <> 0)',
        ),
        isTrue,
      );
      expect(
        iss.routineContains(
          'DeinitializeSetup',
          'RecoverServiceOnAbort and (not FilesInstallStarted)',
        ),
        isTrue,
      );
      expect(
        iss.routineContains('CurStepChanged', 'FilesInstallStarted := True'),
        isTrue,
      );
    },
  );

  for (final scenario in [
    'existing',
    'configure-fails',
    'start-fails',
    'poll-fails',
    'no-helper',
  ]) {
    test('restore existing service: $scenario never removes registration', () async {
      final temp = await Directory.systemTemp.createTemp('restore_failure_');
      addTearDown(() => temp.delete(recursive: true));
      final tools = await Directory(p.join(temp.path, 'tools')).create();
      final context = File(p.join(temp.path, 'context.json'));
      await context.writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'origin': 'service',
          'targetVersion': '3.6.3',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'serviceExists': true,
          'serviceConfig': {'ObjectName': 'LocalSystem'},
        }),
      );
      if (scenario != 'no-helper') {
        await File(p.join(tools.path, 'service_utils.ps1')).writeAsString(
          'function Wait-ServiceStopped { return \$true }\n'
          'function Wait-ServiceRunning { return \$${scenario == 'poll-fails' ? 'false' : 'true'} }\n',
        );
      }
      // Copy only dependencies into the fixture, so missing-helper means missing
      // from BOTH lookup locations and no machine service is ever touched.
      for (final name in ['restore_update_state.ps1', 'encoding_utils.ps1']) {
        await File(p.join('installer', name)).copy(p.join(temp.path, name));
      }
      final nssm = File(p.join(temp.path, 'nssm.cmd'));
      await nssm.writeAsString(
        '@echo off\r\necho %*>>"%NSSM_LOG_PATH%"\r\n'
        '${scenario == 'configure-fails' ? 'if "%1"=="set" exit /b 1\r\n' : ''}'
        '${scenario == 'start-fails' ? 'if "%1"=="start" exit /b 1\r\n' : ''}'
        'exit /b 0\r\n',
      );
      final wrapper = File(p.join(temp.path, 'run.ps1'));
      await wrapper.writeAsString(r'''
function global:Get-Service { param($Name, $ErrorAction) return [pscustomobject]@{Status='Stopped'} }
& "$PSScriptRoot\restore_update_state.ps1" -ContextPath "$PSScriptRoot\context.json" -AppPath "$PSScriptRoot\app.exe" -AppDirectory $PSScriptRoot -NssmPath "$PSScriptRoot\nssm.cmd"
exit $LASTEXITCODE
''');
      final log = File(p.join(temp.path, 'nssm.log'));
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', wrapper.path],
        environment: {'NSSM_LOG_PATH': log.path},
      );
      expect(
        result.exitCode,
        scenario == 'existing'
            ? 0
            : scenario == 'poll-fails' || scenario == 'no-helper'
            ? 2
            : 1,
        reason: '${result.stdout}\n${result.stderr}',
      );
      final commands = await log.exists() ? await log.readAsString() : '';
      expect(commands, isNot(contains('remove BackupDatabaseService')));
      expect(commands, isNot(contains('install BackupDatabaseService')));
      expect(await context.exists(), scenario != 'existing');
      if (scenario == 'no-helper') expect(commands, isEmpty);
      if (scenario == 'configure-fails') {
        expect(commands, isNot(contains('start BackupDatabaseService')));
      }
    }, skip: !Platform.isWindows);
  }
}
