import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'setup_iss_parser.dart';

Future<SetupIssParser> _loadSetupIssParser() async {
  return SetupIssParser.fromFile(_repoFile(p.join('installer', 'setup.iss')));
}

void main() {
  group('installer static startup contract', () {
    test(
      'setup.iss does not create HKLM Run entry and cleans legacy entries',
      () async {
        final setup = await _repoFile(
          p.join('installer', 'setup.iss'),
        ).readAsString();

        expect(setup, isNot(contains('[Registry]')));
        expect(
          setup,
          contains(
            r'delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "{#MyAppName}" /f',
          ),
        );
        expect(
          setup,
          contains(
            r'delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "BackupDatabase" /f',
          ),
        );
        expect(
          setup,
          contains(
            r'delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "{#MyAppName}" /f',
          ),
        );
      },
    );

    test(
      'setup.iss configures client task and server service startup',
      () async {
        final setup = await _repoFile(
          p.join('installer', 'setup.iss'),
        ).readAsString();

        expect(setup, contains('ShouldLaunchPostInstall'));
        // §audit-2026-05-28: a task de logon do cliente AGORA passa
        // `--mode=client` explicitamente. Sem isso, ao abrir o app a
        // resolucao de modo dependia 100% de {app}\.install_mode — se
        // o arquivo sumisse, o resolver caia no default `server` e a
        // maquina de cliente abria como servidor (socket server etc.).
        expect(
          setup,
          contains('--mode=client --minimized --launch-origin=windows-startup'),
        );
        expect(setup, contains('InstallAndStartServiceFromInstaller'));
        expect(setup, contains('-NonInteractive'));
        expect(setup, contains('-StartAfterInstall'));
        expect(setup, contains('RUNNING confirmed'));
        expect(setup, contains('did not reach RUNNING within polling timeout'));
        expect(setup, contains('nao confirmou RUNNING no tempo de espera'));
        expect(setup, contains('WaitForServiceStopped'));
        expect(setup, contains('WaitForServiceRemoved'));
        expect(setup, contains('Wait-ServiceStopped'));
        expect(setup, contains('Wait-ServiceRemoved'));
        expect(setup, contains('ShouldRemoveMachineConfig'));
        expect(setup, contains('ConfigureRemoteSocketFirewall'));
        expect(setup, contains('openfirewall'));
        expect(setup, contains('localport=9527'));
        expect(setup, contains('TROUBLESHOOTING_SERVICE.md'));
        expect(setup, contains('Troubleshooting do Serviço'));
        expect(setup, contains('STOPPED confirmed'));
        expect(
          setup,
          contains('did not reach STOPPED within polling timeout'),
        );
      },
    );

    test(
      'setup.iss distinguishes merge_env and restore exit code 2',
      () async {
        final setup = await _repoFile(
          p.join('installer', 'setup.iss'),
        ).readAsString();

        expect(setup, contains('RunTempPowerShellScriptEx'));
        expect(setup, contains('MergeExitCode'));
        expect(setup, contains('RestoreExitCode'));
        expect(
          setup,
          contains('merge_env.ps1 exit 2 — chave critica ausente'),
        );
        expect(setup, contains('AUTO_UPDATE_FEED_URL'));
        expect(
          setup,
          contains('instalacao silenciosa segue apos merge_env.ps1 exit 2'),
        );
        expect(
          setup,
          contains('A chave AUTO_UPDATE_FEED_URL nao ficou preenchida'),
        );
        expect(setup, isNot(contains('Abort;')));
        expect(
          setup,
          contains('restore_update_state.ps1 exit 2'),
        );
        expect(
          setup,
          contains('update_context.json preservado para retry'),
        );
      },
    );

    test(
      'setup.iss restores mode and does not uninstall previous version',
      () async {
        final setup = await _repoFile(
          p.join('installer', 'setup.iss'),
        ).readAsString();
        final iss = await _loadSetupIssParser();

        expect(setup, isNot(contains('function FindUninstaller')));
        expect(
          iss.routineContains('InitializeSetup', '/VERYSILENT'),
          isFalse,
        );
        expect(
          iss.routineContains('InitializeSetup', 'unins000.exe'),
          isFalse,
        );
        expect(setup, contains('{param:MODE}'));
        expect(setup, contains(r'{app}\.install_mode'));
        expect(setup, contains('read_json_app_mode.ps1'));
        expect(setup, contains('ResolveSelectedMode'));
        expect(
          setup,
          contains(
            'Silent update: skipping startup task/service install',
          ),
        );
        expect(
          setup,
          contains('restore_update_state owns operational state'),
        );
      },
    );

    test(
      'ResolveSelectedMode does not expand {app} during InitializeWizard',
      () async {
        final iss = await _loadSetupIssParser();

        expect(
          iss.routineContains(
            'ResolveSelectedMode',
            "ExpandConstant('{app}",
          ),
          isFalse,
          reason:
              '{app} is not initialized in InitializeWizard; expanding '
              'it aborts Setup with Internal error',
        );
        expect(
          iss.routineContains(
            'InitializeWizard',
            "ExpandConstant('{app}",
          ),
          isFalse,
        );
        expect(
          iss.routineContains('GetInstallModeFilePath', 'PrevAppDir'),
          isTrue,
        );
        expect(
          iss.routineContains(
            'ResolveSelectedMode',
            'GetInstallModeFilePath',
          ),
          isTrue,
        );
      },
    );

    test(
      'setup.iss treats VC++ redist success codes and hides UI',
      () async {
        final setup = await _repoFile(
          p.join('installer', 'setup.iss'),
        ).readAsString();
        final iss = await _loadSetupIssParser();

        expect(setup, contains('IsVCRedistSuccessExitCode'));
        expect(setup, contains('ExitCode = 1638'));
        expect(setup, contains('ExitCode = 3010'));
        expect(setup, contains('ExitCode = 1641'));
        expect(
          iss.routineContains('PrepareToInstall', 'SW_HIDE'),
          isTrue,
        );
        expect(
          iss.routineContains('PrepareToInstall', 'SW_SHOW'),
          isFalse,
        );
      },
    );

    test(
      'setup.iss detects the app by exact image name and does not kill nssm',
      () async {
        final setup = await _repoFile(
          p.join('installer', 'setup.iss'),
        ).readAsString();
        final iss = await _loadSetupIssParser();

        expect(
          iss.routineContains('IsAppRunning', 'IMAGENAME eq'),
          isTrue,
        );
        expect(setup, isNot(contains("CloseApp('nssm.exe')")));
        expect(setup, isNot(contains('taskkill.exe /IM nssm.exe')));
      },
    );

    test(
      'setup.iss removes client startup task on uninstall',
      () async {
        final iss = await _loadSetupIssParser();
        expect(
          iss.routineContains(
            'CurUninstallStepChanged',
            'DeleteClientStartupTask',
          ),
          isTrue,
        );
        expect(
          iss.routineContains('InitializeUninstall', 'UninstallSilent'),
          isTrue,
        );
      },
    );

    test(
      'setup.iss defaults wizard language to Brazilian Portuguese',
      () async {
        final setup = await _repoFile(
          p.join('installer', 'setup.iss'),
        ).readAsString();
        expect(setup, contains('brazilianportuguese'));
        expect(
          setup,
          contains(r'compiler:Languages\BrazilianPortuguese.isl'),
        );
        expect(setup, contains('compiler:Default.isl'));
      },
    );

    test(
      'setup.iss refreshes Windows icon cache after install',
      () async {
        final iss = await _loadSetupIssParser();

        expect(iss.hasForwardDeclaration('RefreshWindowsIconCache'), isTrue);
        expect(
          iss.routineContains('RefreshWindowsIconCache', 'ie4uinit.exe'),
          isTrue,
        );
        expect(
          iss.routineContains('RefreshWindowsIconCache', '-show'),
          isTrue,
        );
      },
    );

    test(
      'setup.iss desktop shortcuts use executable icon and explicit --mode',
      () async {
        // §audit-2026-05-28: o atalho de desktop foi separado em um para
        // cada modo (Server / Client) e passa `--mode=` explicitamente.
        // Antes existia um unico atalho sem `--mode`, que dependia 100%
        // de `{app}\.install_mode` — se o arquivo sumisse, o resolver
        // caia em "server" por default, abrindo socket server numa
        // maquina instalada como cliente.
        final iss = await _loadSetupIssParser();

        final serverEntry = iss.iconEntry(
          r'{autodesktop}\{#MyAppName} (Server)',
        );
        expect(serverEntry, isNotNull, reason: 'server desktop icon missing');
        expect(
          serverEntry,
          contains(r'IconFilename: "{app}\{#MyAppExeName}"'),
        );
        expect(serverEntry, contains('Tasks: desktopicon'));
        expect(serverEntry, contains('Parameters: "--mode=server"'));
        expect(serverEntry, contains('Check: IsServerMode'));

        final clientEntry = iss.iconEntry(
          r'{autodesktop}\{#MyAppName} (Client)',
        );
        expect(clientEntry, isNotNull, reason: 'client desktop icon missing');
        expect(
          clientEntry,
          contains(r'IconFilename: "{app}\{#MyAppExeName}"'),
        );
        expect(clientEntry, contains('Tasks: desktopicon'));
        expect(clientEntry, contains('Parameters: "--mode=client"'));
        expect(clientEntry, contains('Check: IsClientMode'));
      },
    );

    test(
      'setup.iss creates desktop icon task checked by default',
      () async {
        // §audit-2026-05-28: Inno Setup [Tasks] vem checadas por
        // default. NAO existe `Flags: checked` (ISCC 6.6.1 rejeita
        // como "unknown flag"). Para garantir o comportamento
        // "checked by default" basta NAO ter `Flags: unchecked`.
        final iss = await _loadSetupIssParser();
        expect(iss.hasTask('desktopicon'), isTrue);
        expect(
          iss.hasTask('desktopicon', hasFlag: 'unchecked'),
          isFalse,
          reason:
              'desktopicon nao pode ter Flags: unchecked '
              '(quebra o "checked by default")',
        );
      },
    );

    test(
      'setup.iss removes legacy and per-mode desktop shortcuts before recreate',
      () async {
        final iss = await _loadSetupIssParser();

        expect(
          iss.hasForwardDeclaration('RemoveExistingDesktopShortcut'),
          isTrue,
        );
        // §audit-2026-05-28: o helper agora limpa tres caminhos:
        // - legado `.lnk` (atalho unico antigo, sem --mode=)
        // - novo `(Server).lnk` e `(Client).lnk`
        expect(
          iss.routineContains(
            'RemoveExistingDesktopShortcut',
            r'{autodesktop}\{#MyAppName}.lnk',
          ),
          isTrue,
        );
        expect(
          iss.routineContains(
            'RemoveExistingDesktopShortcut',
            r'{autodesktop}\{#MyAppName} (Server).lnk',
          ),
          isTrue,
        );
        expect(
          iss.routineContains(
            'RemoveExistingDesktopShortcut',
            r'{autodesktop}\{#MyAppName} (Client).lnk',
          ),
          isTrue,
        );
        // O delete tem que rodar no ssInstall — antes da secao [Icons] do
        // Inno criar o novo .lnk — e somente quando a task desktopicon
        // estiver ativa.
        expect(
          iss.routineContains(
            'CurStepChanged',
            "if (CurStep = ssInstall) and WizardIsTaskSelected('desktopicon')",
          ),
          isTrue,
        );
      },
    );

    test(
      'setup.iss touches desktop shortcut to flush icon cache',
      () async {
        final iss = await _loadSetupIssParser();

        expect(iss.hasForwardDeclaration('TouchDesktopShortcut'), isTrue);
        // Touch agora delega para TouchOneDesktopShortcut por nome de
        // shortcut e cobre os tres caminhos (legado + Server + Client).
        expect(
          iss.routineContains(
            'TouchDesktopShortcut',
            r'{autodesktop}\{#MyAppName} (Server).lnk',
          ),
          isTrue,
        );
        expect(
          iss.routineContains(
            'TouchDesktopShortcut',
            r'{autodesktop}\{#MyAppName} (Client).lnk',
          ),
          isTrue,
        );
        // O helper unitario contem a logica de PowerShell — checa la.
        expect(
          iss.routineContains('TouchOneDesktopShortcut', 'LastWriteTime'),
          isTrue,
        );
        expect(
          iss.routineContains('TouchOneDesktopShortcut', "'powershell.exe'"),
          isTrue,
        );
        expect(
          iss.routineContains('TouchOneDesktopShortcut', "'pwsh.exe'"),
          isTrue,
        );
        expect(iss.contains('function TryTouchShortcutWith'), isTrue);
      },
    );

    test(
      'setup.iss prompts user when app stays running on interactive install',
      () async {
        final iss = await _loadSetupIssParser();

        expect(
          iss.routineContains('PrepareToInstall', 'MB_DEFBUTTON2'),
          isTrue,
        );
        expect(
          iss.routineContains(
            'PrepareToInstall',
            'Instalacao cancelada pelo usuario',
          ),
          isTrue,
        );
        expect(
          iss.routineContains(
            'PrepareToInstall',
            'icone do atalho pode permanecer desatualizado',
          ),
          isTrue,
        );
      },
    );

    test(
      'setup.iss re-stops Windows service in PrepareToInstall before copying files',
      () async {
        // O servico ja e parado em InitializeSetup. Reforco em
        // PrepareToInstall cobre o caso de o NSSM reiniciar entre as fases
        // (usuario passou tempo no wizard) — sem isso, o .exe antigo pode
        // ficar travado em uso e o icone novo nao chega ao disco.
        final iss = await _loadSetupIssParser();
        expect(
          iss.routineContains(
            'PrepareToInstall',
            "StopService('BackupDatabaseService')",
          ),
          isTrue,
        );
      },
    );

    test('self-hosted workflow exposes manual windows smoke suite', () async {
      final workflow = await _repoFile(
        p.join('.github', 'workflows', 'integration-self-hosted.yml'),
      ).readAsString();

      expect(workflow, contains('windows-smoke'));
      expect(workflow, contains('flutter build windows --release'));
      expect(
        workflow,
        contains('test/scripts/windows_single_instance_smoke.ps1'),
      );
    });
  });

  group('installer PowerShell scripts', () {
    test(
      'service_utils timing constants mirror WindowsServiceTimingConfig',
      () async {
        final serviceUtils = await _repoFile(
          p.join('installer', 'service_utils.ps1'),
        ).readAsString();
        final timingConfig = await _repoFile(
          p.join(
            'lib',
            'infrastructure',
            'external',
            'system',
            'windows_service',
            'windows_service_timing_config.dart',
          ),
        ).readAsString();

        expect(
          serviceUtils,
          contains(
            r'$script:ServiceStartPollingInitialDelaySeconds = 3',
          ),
        );
        expect(
          serviceUtils,
          contains(r'$script:ServiceStartPollingIntervalSeconds = 1'),
        );
        expect(
          serviceUtils,
          contains(r'$script:ServiceStartPollingTimeoutSeconds = 30'),
        );
        expect(
          timingConfig,
          contains('startPollingInitialDelay = const Duration(seconds: 3)'),
        );
        expect(
          timingConfig,
          contains('startPollingInterval = const Duration(seconds: 1)'),
        );
        expect(
          timingConfig,
          contains('startPollingTimeout = const Duration(seconds: 30)'),
        );
        expect(serviceUtils, contains('function Wait-ServiceStopped'));
        expect(serviceUtils, contains('function Test-ServiceScQueryStopped'));
        expect(serviceUtils, contains('function Wait-ServiceRemoved'));
        expect(serviceUtils, contains('function ConvertFrom-NssmOutput'));
        expect(serviceUtils, contains('function Get-NssmValue'));
        expect(serviceUtils, contains('-replace "`0"'));
      },
    );

    test(
      'install restore and uninstall wait for service removal',
      () async {
        final install = await _repoFile(
          p.join('installer', 'install_service.ps1'),
        ).readAsString();
        final restore = await _repoFile(
          p.join('installer', 'restore_update_state.ps1'),
        ).readAsString();
        final uninstall = await _repoFile(
          p.join('installer', 'uninstall_service.ps1'),
        ).readAsString();
        final capture = await _repoFile(
          p.join('installer', 'capture_update_context.ps1'),
        ).readAsString();
        final merge = await _repoFile(
          p.join('installer', 'merge_env.ps1'),
        ).readAsString();
        final build = await _repoFile(
          p.join('installer', 'build_installer.py'),
        ).readAsString();

        expect(install, contains('Wait-ServiceRemoved'));
        expect(install, contains('Wait-ServiceStopped'));
        expect(install, contains('Set-NssmCritical -Key "AppNoConsole"'));
        expect(
          install,
          contains(
            'Set-NssmCritical -Key "AppExit" -ExtraArgs @("77", "Exit")',
          ),
        );
        expect(
          install,
          contains(
            'Set-NssmCritical -Key "AppExit" -ExtraArgs @("78", "Exit")',
          ),
        );
        expect(restore, contains('Wait-ServiceRemoved'));
        expect(restore, contains('Wait-ServiceStopped'));
        expect(restore, contains('Test-SupportedServiceAccount'));
        expect(restore, contains('RUNNING nao foi confirmado por polling'));
        expect(uninstall, contains('Wait-ServiceRemoved'));
        expect(uninstall, contains('NonInteractive'));
        expect(capture, contains('service_utils.ps1'));
        expect(merge, contains('Read-Utf8NoBomFile'));
        expect(restore, contains('Read-Utf8NoBomFile'));
        expect(
          build,
          contains(
            '727d1e42275c605e0f04aba98095c38a8e1e46def453cdffce42869428aa6743',
          ),
        );
      },
    );

    test(
      'ConvertFrom-NssmOutput strips UTF-16 null bytes',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'nssm_utf16_strip_test',
        );
        final utilsPath = p.normalize(
          p.join(Directory.current.path, 'installer', 'service_utils.ps1'),
        );
        final scriptPath = p.join(tempDir.path, 'strip.ps1');
        await File(scriptPath).writeAsString(
          ". '$utilsPath'\n"
          "\$v = 'A' + [char]0 + 'p' + [char]0 + 'p'\n"
          'Write-Output (ConvertFrom-NssmOutput -Value \$v)\n',
        );

        final result = await Process.run('powershell.exe', <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptPath,
        ]);
        expect(
          result.exitCode,
          0,
          reason: 'stderr=${result.stderr} stdout=${result.stdout}',
        );
        expect(result.stdout.toString().trim(), 'App');
        await _deleteTempDirBestEffort(tempDir);
      },
      skip: !Platform.isWindows,
    );

    test(
      'restore_update_state documents exit 2 and preserves context on timeout',
      () async {
        final restoreScript = await _repoFile(
          p.join('installer', 'restore_update_state.ps1'),
        ).readAsString();

        expect(restoreScript, contains('Exit codes'));
        expect(restoreScript, contains('exit 2'));
        expect(
          restoreScript,
          contains('update_context.json e PRESERVADO'),
        );
        expect(
          restoreScript,
          contains('Exit 2: update_context.json preservado para retry'),
        );
        expect(
          restoreScript,
          contains(r'install $ServiceName "`"$AppPath`""'),
        );
      },
    );

    test(
      'merge_env preserves existing values and fills missing keys',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('merge_env_test');
        final examplePath = p.join(tempDir.path, '.env.example');
        final targetPath = p.join(tempDir.path, '.env');
        final backupPath = p.join(tempDir.path, '.env.bak');

        // `AUTO_UPDATE_FEED_URL` é chave crítica (§audit-2026-05-28).
        // Sem ela presente em `.env.example` + após merge, o script
        // sai com exit 2 — comportamento intencional.
        await File(
          examplePath,
        ).writeAsString(
          'A=1\nB=2\nD=4\nAUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n',
        );
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
        expect(merged, contains('AUTO_UPDATE_FEED_URL=https://example.com'));
        expect(RegExp(r'^B=2$', multiLine: true).hasMatch(merged), isFalse);

        await _deleteTempDirBestEffort(tempDir);
      },
      skip: !Platform.isWindows,
    );

    test(
      'merge_env exits with code 2 when critical key AUTO_UPDATE_FEED_URL '
      'missing',
      () async {
        // §audit-2026-05-28: regressao do bug que motivou a auditoria.
        // Sem AUTO_UPDATE_FEED_URL no merge final, o instalador
        // DEVE sinalizar exit code 2 para o caller (setup.iss) logar
        // warning explicito.
        final tempDir = await Directory.systemTemp.createTemp(
          'merge_env_critical_test',
        );
        final examplePath = p.join(tempDir.path, '.env.example');
        final targetPath = p.join(tempDir.path, '.env');

        await File(examplePath).writeAsString('A=1\nB=2\n');
        await File(targetPath).writeAsString('A=existing\n');

        final result = await _runPowerShellScript(
          scriptRelativePath: p.join('installer', 'merge_env.ps1'),
          arguments: <String>[
            '-ExamplePath',
            examplePath,
            '-TargetPath',
            targetPath,
          ],
        );

        expect(result.exitCode, 2);
        expect(
          result.stderr.toString(),
          contains('AUTO_UPDATE_FEED_URL'),
        );

        await _deleteTempDirBestEffort(tempDir);
      },
      skip: !Platform.isWindows,
    );

    test(
      'merge_env always overwrites APP_VERSION (system-managed key)',
      () async {
        // §audit-2026-05-28: regressao do bug em que `APP_VERSION=2.1.3`
        // ficava stale no ProgramData mesmo apos varios upgrades porque
        // o merge antigo SO adicionava chaves novas (preservava valor
        // existente). Agora APP_VERSION e system-managed: sempre vem
        // do .env.example, refletindo a versao real do instalador.
        final tempDir = await Directory.systemTemp.createTemp(
          'merge_env_appversion_test',
        );
        final examplePath = p.join(tempDir.path, '.env.example');
        final targetPath = p.join(tempDir.path, '.env');

        await File(examplePath).writeAsString(
          'APP_VERSION=3.3.1\nAUTO_UPDATE_FEED_URL=https://example.com/x.xml\n',
        );
        // .env "antigo" com versao stale + override de user
        await File(targetPath).writeAsString(
          'APP_VERSION=2.1.3\nAUTO_UPDATE_FEED_URL=https://example.com/x.xml\n'
          'CUSTOM_USER_VAR=preserve_me\n',
        );

        final result = await _runPowerShellScript(
          scriptRelativePath: p.join('installer', 'merge_env.ps1'),
          arguments: <String>[
            '-ExamplePath',
            examplePath,
            '-TargetPath',
            targetPath,
          ],
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());

        final merged = await File(targetPath).readAsString();
        expect(merged, contains('APP_VERSION=3.3.1'));
        expect(
          RegExp(r'^APP_VERSION=2\.1\.3$', multiLine: true).hasMatch(merged),
          isFalse,
          reason: 'system-managed key must be overwritten',
        );
        expect(
          merged,
          contains('CUSTOM_USER_VAR=preserve_me'),
          reason: 'user override must be preserved',
        );

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
      r'restore_update_state accepts NT AUTHORITY\SYSTEM and System aliases',
      () async {
        for (final account in <String>[
          r'NT AUTHORITY\SYSTEM',
          'System',
          'localsystem',
        ]) {
          final tempDir = await Directory.systemTemp.createTemp(
            'restore_account_alias_test',
          );
          final nssmLogPath = p.join(tempDir.path, 'nssm.log');
          final nssmPath = p.join(tempDir.path, 'nssm.cmd');
          final contextPath = p.join(tempDir.path, 'update_context.json');

          await File(nssmPath).writeAsString(
            '@echo off\r\necho %*>>"%NSSM_LOG_PATH%"\r\nexit /b 0\r\n',
          );
          await _writeStubServiceUtils(tempDir);
          await File(contextPath).writeAsString(
            jsonEncode(<String, Object?>{
              'schemaVersion': 2,
              'contextId': 'alias-context-$account',
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
                'ObjectName': account,
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

          expect(
            result.exitCode,
            0,
            reason:
                'Account "$account" should be accepted as LocalSystem alias. '
                'stderr=${result.stderr}',
          );
          final nssmLog = await File(nssmLogPath).readAsString();
          expect(
            nssmLog,
            contains('set BackupDatabaseService ObjectName LocalSystem'),
            reason: 'Failed normalizing account "$account" to LocalSystem',
          );

          await _deleteTempDirBestEffort(tempDir);
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'restore_update_state rejects custom service accounts',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'restore_account_custom_test',
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
            'contextId': 'custom-account-context',
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
              'ObjectName': r'CONTOSO\backupsvc',
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

        expect(result.exitCode, 2);
        expect(
          result.stderr.toString(),
          contains('LocalSystem'),
          reason: 'Error message should mention LocalSystem requirement',
        );
        expect(await File(nssmLogPath).exists(), isFalse);
        expect(await File(contextPath).exists(), isTrue);

        await _deleteTempDirBestEffort(tempDir);
      },
      skip: !Platform.isWindows,
    );

    test(
      'restore_update_state skips service replay for UI origin',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'restore_ui_skips_service_test',
        );
        final nssmLogPath = p.join(tempDir.path, 'nssm.log');
        final nssmPath = p.join(tempDir.path, 'nssm.cmd');
        final markerPath = p.join(tempDir.path, 'relaunch_args.txt');
        final appScriptPath = p.join(tempDir.path, 'write_args.ps1');
        final contextPath = p.join(tempDir.path, 'update_context.json');

        await File(nssmPath).writeAsString(
          '@echo off\r\necho %*>>"%NSSM_LOG_PATH%"\r\nexit /b 0\r\n',
        );
        await File(appScriptPath).writeAsString(
          r'Set-Content -Path "$env:MARKER_PATH" -Value ($args -join "`n")',
        );
        await File(contextPath).writeAsString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 2,
            'contextId': 'ui-skips-service',
            'origin': 'ui',
            'appMode': 'server',
            'currentVersion': '3.0.1',
            'targetVersion': '3.0.2',
            'relaunchArguments': <String>[
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              appScriptPath,
              '--mode=server',
            ],
            'executablePath': 'powershell.exe',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 30))
                .toUtc()
                .toIso8601String(),
            'serviceName': 'BackupDatabaseService',
            'serviceExists': true,
            'serviceConfig': <String, Object?>{
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
            'powershell.exe',
            '-AppDirectory',
            tempDir.path,
            '-NssmPath',
            nssmPath,
          ],
          environment: <String, String>{
            'NSSM_LOG_PATH': nssmLogPath,
            'MARKER_PATH': markerPath,
          },
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(await File(nssmLogPath).exists(), isFalse);
        expect(await File(contextPath).exists(), isFalse);
        final markerFile = await _waitForFile(markerPath);
        expect(await markerFile.readAsString(), contains('--mode=server'));

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
        await _writeStubServiceUtils(tempDir);
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
        expect(
          nssmLog,
          contains('set BackupDatabaseService AppExit 77 Exit'),
        );
        expect(
          nssmLog,
          contains('set BackupDatabaseService AppExit 78 Exit'),
          reason: 'handoff exit code (78) must be preserved on restore',
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

        final decoded = jsonDecode(
          await File(contextPath).readAsString(),
        ) as Map<String, Object?>;
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

File _repoFile(String relativePath) {
  return File(p.join(Directory.current.path, relativePath));
}

Future<void> _writeStubServiceUtils(Directory appDir) async {
  final toolsDir = Directory(p.join(appDir.path, 'tools'));
  await toolsDir.create(recursive: true);
  await File(p.join(toolsDir.path, 'service_utils.ps1')).writeAsString(
    'function Wait-ServiceRunning { param([string]\$ServiceName) return \$true }\n'
    'function Wait-ServiceStopped { param([string]\$ServiceName) return \$true }\n'
    'function Wait-ServiceRemoved { param([string]\$ServiceName) return \$true }\n',
  );
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
