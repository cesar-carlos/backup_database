import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('installer PowerShell scripts', () {
    test(
      'merge_env preserves existing values and fills missing keys',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('merge_env_test');
        final examplePath = p.join(tempDir.path, '.env.example');
        final targetPath = p.join(tempDir.path, '.env');
        final backupPath = p.join(tempDir.path, '.env.bak');

        await File(examplePath).writeAsString('A=1\nB=2\nD=4\n');
        await File(targetPath).writeAsString('B=9\nC=3\n');

        final result = await _runPowerShellScript(
          scriptRelativePath: p.join('installer', 'merge_env.ps1'),
          arguments: <String>[
            '-ExamplePath',
            examplePath,
            '-TargetPath',
            targetPath,
            '-BackupPath',
            backupPath,
          ],
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());

        final merged = await File(targetPath).readAsString();
        expect(merged, contains('A=1'));
        expect(merged, contains('B=9'));
        expect(merged, contains('C=3'));
        expect(merged, contains('D=4'));
        expect(RegExp(r'^B=2$', multiLine: true).hasMatch(merged), isFalse);

        await _deleteTempDirBestEffort(tempDir);
      },
      skip: !Platform.isWindows,
    );

    test(
      'restore_update_state ignores expired context and deletes it',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'restore_context_expired_test',
        );
        final markerPath = p.join(tempDir.path, 'should_not_exist.txt');
        final appScriptPath = p.join(tempDir.path, 'write_marker.ps1');
        final contextPath = p.join(tempDir.path, 'update_context.json');

        await File(appScriptPath).writeAsString(
          r'Set-Content -Path "$env:MARKER_PATH" -Value ($args -join "`n")',
        );
        await File(contextPath).writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 2,
            'contextId': 'expired-context',
            'origin': 'ui',
            'appMode': 'client',
            'currentVersion': '3.0.1',
            'targetVersion': '3.0.2',
            'relaunchArguments': <String>[
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              appScriptPath,
            ],
            'executablePath': 'powershell.exe',
            'createdAt': DateTime.now()
                .subtract(const Duration(hours: 2))
                .toUtc()
                .toIso8601String(),
            'expiresAt': DateTime.now()
                .subtract(const Duration(minutes: 10))
                .toUtc()
                .toIso8601String(),
            'serviceName': 'BackupDatabaseService',
            'serviceExists': false,
          }),
        );

        final result = await _runPowerShellScript(
          scriptRelativePath: p.join('installer', 'restore_update_state.ps1'),
          arguments: <String>[
            '-ContextPath',
            contextPath,
            '-AppPath',
            'powershell.exe',
            '-AppDirectory',
            tempDir.path,
            '-NssmPath',
            p.join(tempDir.path, 'nssm.exe'),
          ],
          environment: <String, String>{'MARKER_PATH': markerPath},
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(await File(contextPath).exists(), isFalse);
        expect(await File(markerPath).exists(), isFalse);

        await _deleteTempDirBestEffort(tempDir);
      },
      skip: !Platform.isWindows,
    );

    test(
      'restore_update_state relaunches UI with original arguments',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'restore_context_ui_test',
        );
        final markerPath = p.join(tempDir.path, 'relaunch_args.txt');
        final appScriptPath = p.join(tempDir.path, 'write_args.ps1');
        final contextPath = p.join(tempDir.path, 'update_context.json');

        await File(appScriptPath).writeAsString(
          r'Set-Content -Path "$env:MARKER_PATH" -Value ($args -join "`n")',
        );
        await File(contextPath).writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 2,
            'contextId': 'ui-context',
            'origin': 'ui',
            'appMode': 'client',
            'currentVersion': '3.0.1',
            'targetVersion': '3.0.2',
            'relaunchArguments': <String>[
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              appScriptPath,
              '--mode=client',
              '--schedule-id=42',
            ],
            'executablePath': 'powershell.exe',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 30))
                .toUtc()
                .toIso8601String(),
            'serviceName': 'BackupDatabaseService',
            'serviceExists': false,
          }),
        );

        final result = await _runPowerShellScript(
          scriptRelativePath: p.join('installer', 'restore_update_state.ps1'),
          arguments: <String>[
            '-ContextPath',
            contextPath,
            '-AppPath',
            'powershell.exe',
            '-AppDirectory',
            tempDir.path,
            '-NssmPath',
            p.join(tempDir.path, 'nssm.exe'),
          ],
          environment: <String, String>{'MARKER_PATH': markerPath},
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final markerFile = await _waitForFile(markerPath);
        final relaunchedArgs = await markerFile.readAsString();
        expect(relaunchedArgs, contains('--mode=client'));
        expect(relaunchedArgs, contains('--schedule-id=42'));
        expect(await File(contextPath).exists(), isFalse);

        await _deleteTempDirBestEffort(tempDir);
      },
      skip: !Platform.isWindows,
    );

    test(
      'restore_update_state replays LocalSystem service configuration',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'restore_context_service_test',
        );
        final nssmLogPath = p.join(tempDir.path, 'nssm.log');
        final nssmPath = p.join(tempDir.path, 'nssm.cmd');
        final contextPath = p.join(tempDir.path, 'update_context.json');

        await File(nssmPath).writeAsString(
          '@echo off\r\necho %*>>"%NSSM_LOG_PATH%"\r\nexit /b 0\r\n',
        );
        await File(contextPath).writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 2,
            'contextId': 'service-context',
            'origin': 'service',
            'appMode': 'server',
            'currentVersion': '3.0.1',
            'targetVersion': '3.0.2',
            'relaunchArguments': const <String>[],
            'executablePath':
                r'C:\Program Files\Backup Database\backup_database.exe',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 30))
                .toUtc()
                .toIso8601String(),
            'serviceName': 'BackupDatabaseService',
            'serviceExists': true,
            'serviceConfig': <String, Object?>{
              'AppParameters': '--mode=server --minimized --run-as-service',
              'AppDirectory': tempDir.path,
              'AppEnvironmentExtra': 'SERVICE_MODE=server',
              'DisplayName': 'Backup Database Service',
              'Description': 'Servico de backup',
              'Start': 'SERVICE_AUTO_START',
              'AppStdout': p.join(tempDir.path, 'stdout.log'),
              'AppStderr': p.join(tempDir.path, 'stderr.log'),
              'AppRestartDelay': '60000',
              'AppNoConsole': '1',
              'ObjectName': 'LocalSystem',
            },
          }),
        );

        final result = await _runPowerShellScript(
          scriptRelativePath: p.join('installer', 'restore_update_state.ps1'),
          arguments: <String>[
            '-ContextPath',
            contextPath,
            '-AppPath',
            r'C:\Program Files\Backup Database\backup_database.exe',
            '-AppDirectory',
            tempDir.path,
            '-NssmPath',
            nssmPath,
          ],
          environment: <String, String>{'NSSM_LOG_PATH': nssmLogPath},
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final nssmLog = await File(nssmLogPath).readAsString();
        expect(nssmLog, contains('install BackupDatabaseService'));
        expect(
          nssmLog,
          contains('set BackupDatabaseService ObjectName LocalSystem'),
        );
        expect(nssmLog, contains('start BackupDatabaseService'));
        expect(await File(contextPath).exists(), isFalse);

        await _deleteTempDirBestEffort(tempDir);
      },
      skip: !Platform.isWindows,
    );

    test(
      'capture_update_context enriches JSON, writes UTF-8 without BOM',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'capture_update_context_test',
        );
        final contextPath = p.join(tempDir.path, 'update_context.json');

        await File(contextPath).writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 2,
            'contextId': 'capture-test',
            'origin': 'ui',
            'appMode': 'client',
            'currentVersion': '1.0.0',
            'targetVersion': '1.0.1',
            'relaunchArguments': <String>[],
            'executablePath': r'C:\fake\backup_database.exe',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 30))
                .toUtc()
                .toIso8601String(),
          }),
        );

        final result = await _runPowerShellScript(
          scriptRelativePath: p.join(
            'installer',
            'capture_update_context.ps1',
          ),
          arguments: <String>['-ContextPath', contextPath],
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());

        final bytes = await File(contextPath).readAsBytes();
        expect(
          bytes.length >= 3 &&
              bytes[0] == 0xEF &&
              bytes[1] == 0xBB &&
              bytes[2] == 0xBF,
          isFalse,
          reason: 'Output must be UTF-8 without BOM',
        );

        final decoded =
            jsonDecode(await File(contextPath).readAsString())
                as Map<String, Object?>;
        expect(decoded['serviceExists'], isA<bool>());
        expect(decoded['capturedAt'], isA<String>());
        expect((decoded['capturedAt']! as String).isNotEmpty, isTrue);
        if (decoded['serviceExists'] == false) {
          expect(decoded['serviceConfig'], isNull);
        }

        await _deleteTempDirBestEffort(tempDir);
      },
      skip: !Platform.isWindows,
    );
  });
}


Future<void> _deleteTempDirBestEffort(Directory directory) async {
  const maxAttempts = 8;
  const delay = Duration(milliseconds: 150);
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    } on PathAccessException {
      if (attempt == maxAttempts - 1) {
        rethrow;
      }
      await Future<void>.delayed(delay);
    }
  }
}
Future<ProcessResult> _runPowerShellScript({
  required String scriptRelativePath,
  required List<String> arguments,
  Map<String, String>? environment,
}) {
  final scriptPath = p.join(Directory.current.path, scriptRelativePath);
  return Process.run(
    'powershell.exe',
    <String>[
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptPath,
      ...arguments,
    ],
    environment: environment,
  );
}

Future<File> _waitForFile(String path) async {
  final file = File(path);
  for (var i = 0; i < 20; i++) {
    if (await file.exists()) {
      return file;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError('Timed out waiting for file: $path');
}
