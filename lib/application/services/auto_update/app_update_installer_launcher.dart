import 'dart:io';

import 'package:backup_database/application/services/auto_update/app_update_types.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/utils/logger_service.dart';

class AppUpdateInstallerLauncher {
  AppUpdateInstallerLauncher({
    required this.detachedProcessStarter,
    required this.processAliveCheck,
    required this.spawnGracePeriod,
  });

  static const Duration _pollInterval = Duration(milliseconds: 250);

  final DetachedProcessStarter detachedProcessStarter;
  final ProcessAliveCheck processAliveCheck;
  final Duration spawnGracePeriod;

  /// Argumentos do Inno Setup para auto-update silencioso.
  ///
  /// `/MODE=` preserva server vs client no wizard customizado, que o Inno
  /// nao restaura via `UsePreviousTasks`. `unified` cai em `server`.
  static List<String> installerArgumentsFor(AppMode mode) {
    final modeArg = mode == AppMode.client ? 'client' : 'server';
    return <String>[
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/MODE=$modeArg',
    ];
  }

  Future<DetachedProcessHandle?> launch(
    File installer, {
    required AppMode mode,
  }) async {
    final arguments = installerArgumentsFor(mode);
    LoggerService.info(
      'Iniciando instalador silencioso: ${installer.path} '
      '${arguments.join(' ')}',
    );
    return detachedProcessStarter(installer.path, arguments);
  }

  /// Confirma que o instalador detached realmente iniciou. Estrategia:
  /// 1. Pula a checagem se o starter custom nao expoe pid (testes).
  /// 2. Espera ate [spawnGracePeriod] verificando o pid em
  ///    janelas curtas. Exige evidencia positiva (pid vivo ao menos uma vez).
  /// 3. Se a janela expira sem evidencia, falha o handoff (fail-closed).
  Future<bool> waitForSpawn(DetachedProcessHandle? handle) async {
    if (handle == null) {
      // Fallback retro: starter custom (ex.: testes) que nao expoe pid;
      // assume sucesso para preservar o comportamento anterior.
      return true;
    }

    final deadline = DateTime.now().add(spawnGracePeriod);
    var consecutiveDeadChecks = 0;
    var sawAliveOnce = false;

    while (DateTime.now().isBefore(deadline)) {
      if (processAliveCheck(handle.pid)) {
        sawAliveOnce = true;
        consecutiveDeadChecks = 0;
      } else {
        consecutiveDeadChecks++;
        if (consecutiveDeadChecks >= 2 && !sawAliveOnce) {
          return false;
        }
      }
      await Future<void>.delayed(_pollInterval);
    }

    return sawAliveOnce || processAliveCheck(handle.pid);
  }
}
