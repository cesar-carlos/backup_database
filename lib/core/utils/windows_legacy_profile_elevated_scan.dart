import 'dart:developer' as developer;
import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/elevated_legacy_profile_scan_outcome.dart';
import 'package:backup_database/core/utils/machine_storage_migration.dart';
import 'package:backup_database/core/utils/windows_shell_execute_runas.dart';
import 'package:path/path.dart' as p;

const String _logName = 'elevated_legacy_profile_scan';

String _psSingleQuotedPath(String path) => "'${path.replaceAll("'", "''")}'";

const String _elevatedScanPs1Body = r'''
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$OutputPath
)

$skipped = @('Public', 'Default', 'Default User', 'All Users')
$names = @('backup_database', 'backup_database_client')
$results = New-Object System.Collections.Generic.List[string]

Get-ChildItem -LiteralPath 'C:\Users' -Directory -ErrorAction SilentlyContinue |
  ForEach-Object {
    if ($skipped -contains $_.Name) {
      return
    }
    $legacy = Join-Path $_.FullName 'AppData\Roaming\Backup Database'
    if (-not (Test-Path -LiteralPath $legacy)) {
      return
    }
    $include = $false
    foreach ($n in $names) {
      $db = Join-Path $legacy ($n + '.db')
      if (-not (Test-Path -LiteralPath $db)) {
        continue
      }
      if ((Get-Item -LiteralPath $db).Length -eq 0) {
        continue
      }
      $fs = [System.IO.File]::OpenRead($db)
      try {
        $hdr = New-Object byte[] 16
        if ($fs.Read($hdr, 0, 16) -lt 16) {
          continue
        }
      } finally {
        $fs.Dispose()
      }
      $prefix = [System.Text.Encoding]::ASCII.GetString($hdr, 0, 15)
      if ($prefix -ne 'SQLite format 3') {
        continue
      }
      if ($hdr[15] -ne 0) {
        continue
      }
      $include = $true
      break
    }
    if ($include) {
      $results.Add($legacy) | Out-Null
    }
  }

$dir = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $dir | Out-Null
@{
  schemaVersion = 1
  paths = @($results | Sort-Object -Unique)
  scannedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
''';

String? _legacyProfileScannerExePath() {
  if (!Platform.isWindows) {
    return null;
  }
  return p.join(
    p.dirname(Platform.resolvedExecutable),
    'legacy_profile_scanner.exe',
  );
}

Future<ElevatedLegacyProfileScanOutcome?> _runNativeScannerElevated(
  File outputJsonFile,
) async {
  final exe = _legacyProfileScannerExePath();
  if (exe == null || !await File(exe).exists()) {
    return null;
  }

  developer.log(
    'Using native legacy_profile_scanner.exe for elevated profile scan',
    name: _logName,
  );

  final params = quotedLegacyScannerOutputArgument(outputJsonFile.path);
  final shell = await shellExecuteRunAsAndWait(
    executablePath: exe,
    parameters: params,
  );

  if (!shell.shellExecuteOk) {
    final err = shell.win32LastError;
    if (err == kWin32ErrorCancelled) {
      return ElevatedLegacyProfileScanOutcome.failed(
        failureKind: ElevatedLegacyScanFailureKind.userDismissedUac,
        methodUsed: LegacyElevatedScanMethod.nativeExecutable,
        win32LastError: err,
      );
    }
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.elevationLaunchFailed,
      methodUsed: LegacyElevatedScanMethod.nativeExecutable,
      win32LastError: err,
    );
  }

  final code = shell.processExitCode;
  if (code == null) {
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.elevationLaunchFailed,
      methodUsed: LegacyElevatedScanMethod.nativeExecutable,
    );
  }
  if (code != 0) {
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.elevatedProcessFailed,
      exitCode: code,
      methodUsed: LegacyElevatedScanMethod.nativeExecutable,
    );
  }
  if (!await outputJsonFile.exists()) {
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.missingOutputFile,
      methodUsed: LegacyElevatedScanMethod.nativeExecutable,
    );
  }
  final raw = await outputJsonFile.readAsString();
  return decodeElevatedLegacyProfileScanJson(
    raw,
    '',
    methodUsed: LegacyElevatedScanMethod.nativeExecutable,
  );
}

Future<ElevatedLegacyProfileScanOutcome> _runPowerShellElevatedScan(
  File outputJsonFile,
) async {
  developer.log(
    'Using PowerShell fallback for elevated profile scan',
    name: _logName,
  );

  final stamp = DateTime.now().millisecondsSinceEpoch;
  final scanScript = File(
    p.join(Directory.systemTemp.path, 'bd_r1_elevated_scan_$stamp.ps1'),
  );
  final launcherScript = File(
    p.join(Directory.systemTemp.path, 'bd_r1_elevated_launch_$stamp.ps1'),
  );

  try {
    await scanScript.writeAsString(_elevatedScanPs1Body, flush: true);

    final launcherBody =
        '''
\$ErrorActionPreference = 'Stop'
\$p = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  ${_psSingleQuotedPath(scanScript.path)},
  ${_psSingleQuotedPath(outputJsonFile.path)}
) -PassThru -Wait
if (\$null -eq \$p) { exit 1 }
exit \$p.ExitCode
''';
    await launcherScript.writeAsString(launcherBody, flush: true);

    final proc = await Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        launcherScript.path,
      ],
    );

    final stderr = proc.stderr.toString().trim();
    if (proc.exitCode != 0) {
      final low = stderr.toLowerCase();
      final looksLikeUacCancel =
          low.contains('cancel') ||
          low.contains('cancelled') ||
          low.contains('canceled') ||
          low.contains('operation was cancelled') ||
          low.contains('operation was canceled');
      return ElevatedLegacyProfileScanOutcome.failed(
        failureKind: looksLikeUacCancel
            ? ElevatedLegacyScanFailureKind.userDismissedUac
            : ElevatedLegacyScanFailureKind.elevatedProcessFailed,
        exitCode: proc.exitCode,
        stderr: stderr,
        methodUsed: LegacyElevatedScanMethod.powershell,
      );
    }

    if (!await outputJsonFile.exists()) {
      return ElevatedLegacyProfileScanOutcome.failed(
        failureKind: ElevatedLegacyScanFailureKind.missingOutputFile,
        stderr: stderr,
        methodUsed: LegacyElevatedScanMethod.powershell,
      );
    }

    final raw = await outputJsonFile.readAsString();
    return decodeElevatedLegacyProfileScanJson(
      raw,
      stderr,
      methodUsed: LegacyElevatedScanMethod.powershell,
    );
  } on Object {
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.unexpectedError,
      methodUsed: LegacyElevatedScanMethod.powershell,
    );
  } finally {
    try {
      if (await scanScript.exists()) {
        await scanScript.delete();
      }
    } on Object {
      // ignore
    }
    try {
      if (await launcherScript.exists()) {
        await launcherScript.delete();
      }
    } on Object {
      // ignore
    }
  }
}

Future<ElevatedLegacyProfileScanOutcome> runElevatedLegacyProfileScan({
  required File outputJsonFile,
}) async {
  if (!Platform.isWindows) {
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.notWindows,
    );
  }

  await outputJsonFile.parent.create(recursive: true);

  try {
    final nativeOutcome = await _runNativeScannerElevated(outputJsonFile);
    if (nativeOutcome != null) {
      return nativeOutcome;
    }

    return await _runPowerShellElevatedScan(outputJsonFile);
  } on Object catch (e, s) {
    developer.log(
      'Elevated legacy profile scan failed',
      name: _logName,
      error: e,
      stackTrace: s,
    );
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.unexpectedError,
    );
  } finally {
    try {
      if (await outputJsonFile.exists()) {
        await outputJsonFile.delete();
      }
    } on Object {
      // ignore
    }
  }
}

Future<ElevatedLegacyProfileScanOutcome>
runElevatedLegacyProfileScanToMachineConfig() async {
  final out = File(
    p.join(
      Directory.systemTemp.path,
      'bd_r1_elevated_${DateTime.now().microsecondsSinceEpoch}.json',
    ),
  );
  return runElevatedLegacyProfileScan(outputJsonFile: out);
}

Future<List<String>> mergeLegacyProfilePathsExcludingCurrentUser({
  required List<String> elevatedPaths,
  Future<List<String>> Function()? normalScanForTest,
  String? currentUserLegacyPathOverrideForTest,
}) async {
  final legacyPath =
      currentUserLegacyPathOverrideForTest ??
      (await resolveLegacyWindowsUserAppDataDirectory())?.path;
  final currentNormalized = legacyPath != null
      ? p.normalize(legacyPath).toLowerCase()
      : null;
  final merged = <String>{...elevatedPaths};
  final normalScan = normalScanForTest != null
      ? await normalScanForTest()
      : await findLegacyBackupDatabasePathsOutsideCurrentUser();
  merged.addAll(normalScan);
  if (currentNormalized == null) {
    return merged.toList()..sort();
  }
  return merged
      .where((e) => p.normalize(e).toLowerCase() != currentNormalized)
      .toList()
    ..sort();
}
