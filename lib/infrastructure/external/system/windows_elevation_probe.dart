import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_elevation_probe.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:meta/meta.dart';

/// Implementação Windows de [IElevationProbe] que sondaja em paralelo:
///
///   1. **UAC ativo** via registry
///      `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System!EnableLUA`;
///   2. **Token elevado** via `WindowsPrincipal.IsInRole(Administrator)`
///      do .NET (disponível em todo Windows com PowerShell ≥ 2.0).
///
/// Segue o mesmo pattern do `ServiceAccountProbe`: PowerShell rodado
/// pelo `ProcessService` já existente — timeout consistente, logs
/// estruturados, fácil mock nos testes.
///
/// **Por que PowerShell e não FFI direto?**
///   - O conjunto de símbolos exportados pelo pacote `win32` varia
///     entre versões (5.x → 6.x), e amarrar a detecção a uma API
///     específica criaria dependência frágil.
///   - `ProcessService.run` já é usado em outros probes Win
///     (`ServiceAccountProbe`) — preservar consistência simplifica
///     leitura/manutenção.
///   - Timeout de 5 s + cap de output são suficientes; perf não
///     importa (chamado uma vez por boot do AutoUpdate).
class WindowsElevationProbe implements IElevationProbe {
  WindowsElevationProbe({
    required ps.ProcessService processService,
    @visibleForTesting Duration probeTimeout = _defaultTimeout,
  }) : _processService = processService,
       _probeTimeout = probeTimeout;

  /// Construtor legado para callers que ainda não foram migrados
  /// para receber `ProcessService` via DI.
  factory WindowsElevationProbe.legacy() {
    return WindowsElevationProbe(processService: ps.ProcessService());
  }

  static const Duration _defaultTimeout = Duration(seconds: 5);

  final ps.ProcessService _processService;
  final Duration _probeTimeout;

  /// Sentinela usada pelo script PowerShell para separar valores no
  /// stdout. Escolhido para nunca aparecer em `True`/`False`/diagnostic
  /// strings normais.
  @visibleForTesting
  static const String separator = '|';

  /// Script PowerShell que escreve **exatamente uma** linha em stdout
  /// com o formato `uac=<bool>|elevated=<bool>` (ou `null` quando a
  /// detecção falhou em algum bloco). Exposto para teste poder
  /// verificar a forma do output esperado.
  @visibleForTesting
  static const String probeScript = r'''
$uac = $null
try {
  $val = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -ErrorAction Stop).EnableLUA
  $uac = ($val -eq 1)
} catch {
  $uac = $null
}
$elev = $null
try {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  $elev = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
  $elev = $null
}
$uacStr = if ($null -eq $uac) { 'null' } else { $uac.ToString().ToLower() }
$elevStr = if ($null -eq $elev) { 'null' } else { $elev.ToString().ToLower() }
Write-Output ("uac=$uacStr|elevated=$elevStr")
''';

  @override
  Future<ElevationSnapshot> probe() async {
    // Plataforma não-Windows: nenhum prompt UAC a se preocupar.
    // Devolve "elevado/UAC off" para que o readiness check siga
    // pelo caminho normal (sem bloqueio adicional).
    if (!Platform.isWindows) {
      return const ElevationSnapshot(
        uacEnabled: false,
        processIsElevated: true,
        diagnostic: 'non-windows-platform',
      );
    }

    final result = await _processService.run(
      executable: 'powershell.exe',
      arguments: <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        probeScript,
      ],
      timeout: _probeTimeout,
      tag: 'elevation_probe',
    );

    return result.fold(
      (processResult) {
        if (processResult.exitCode != 0) {
          LoggerService.warning(
            '[elevation_probe] PowerShell saiu com '
            'exit=${processResult.exitCode}: ${processResult.stderr}',
          );
          return const ElevationSnapshot(
            uacEnabled: null,
            processIsElevated: null,
            diagnostic: 'powershell-exit-nonzero',
          );
        }
        return parseProbeOutput(processResult.stdout);
      },
      (failure) {
        LoggerService.warning(
          '[elevation_probe] Falha ao executar PowerShell: $failure',
        );
        return const ElevationSnapshot(
          uacEnabled: null,
          processIsElevated: null,
          diagnostic: 'process-service-failure',
        );
      },
    );
  }

  /// Parser **puro** do output do [probeScript] — expõe-se para teste
  /// sem precisar mockar o `ProcessService`.
  ///
  /// Formato esperado: `uac=<true|false|null>|elevated=<true|false|null>`.
  /// Qualquer desvio retorna snapshot com `null/null` + diagnostic.
  @visibleForTesting
  static ElevationSnapshot parseProbeOutput(String rawStdout) {
    final line = rawStdout
        .split('\n')
        .map((l) => l.trim())
        .firstWhere(
          (l) => l.startsWith('uac='),
          orElse: () => '',
        );
    if (line.isEmpty) {
      return const ElevationSnapshot(
        uacEnabled: null,
        processIsElevated: null,
        diagnostic: 'output-missing-marker',
      );
    }
    final parts = line.split(separator);
    bool? uac;
    bool? elev;
    for (final part in parts) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final key = part.substring(0, eq).trim();
      final value = part.substring(eq + 1).trim().toLowerCase();
      final parsed = switch (value) {
        'true' => true,
        'false' => false,
        _ => null,
      };
      if (key == 'uac') uac = parsed;
      if (key == 'elevated') elev = parsed;
    }
    return ElevationSnapshot(
      uacEnabled: uac,
      processIsElevated: elev,
      diagnostic: 'parsed-ok',
    );
  }
}
