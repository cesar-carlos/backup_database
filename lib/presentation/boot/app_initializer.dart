import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/application/services/initial_setup_service.dart';
import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/core.dart';
import 'package:backup_database/core/di/service_locator.dart'
    as service_locator;
import 'package:backup_database/core/utils/schedule_args.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/i_elevation_probe.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:backup_database/presentation/boot/launch_bootstrap_context.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get_it/get_it.dart';

class AppInitializer {
  static Future<void> initialize({required AppMode appMode}) async {
    await _initializeDefaultCredential();
    // Auth providers e auto-update são independentes — paralelizar reduz
    // latência percebida no boot, especialmente em redes lentas onde o
    // initialize de OAuth providers pode ter round-trip não-trivial.
    await Future.wait([
      _initializeAuthProviders(),
      _initializeAutoUpdate(appMode: appMode),
    ]);
  }

  static Future<void> _initializeDefaultCredential() async {
    // A credencial default existe para o **socket server** aceitar conexões
    // de clientes. Em modo cliente não temos socket server (gate em
    // `AppModePolicy.shouldStartSocketServer`) — criar a credencial só
    // polui o `backup_database_client.db` sem utilidade nenhuma.
    if (AppModePolicy.isClient) {
      LoggerService.debug(
        'InitialSetupService.createDefaultCredentialIfNotExists pulado '
        '(modo cliente)',
      );
      return;
    }
    try {
      final initialSetup = service_locator.getIt<InitialSetupService>();
      final result = await initialSetup.createDefaultCredentialIfNotExists();
      if (result != null) {
        LoggerService.info(
          'Credencial padrao criada (Server ID: ${result.serverId})',
        );
      }
    } on Object catch (e) {
      LoggerService.warning('Erro ao criar credencial padrao: $e');
    }
  }

  static Future<void> _initializeAuthProviders() async {
    // Google e Dropbox são independentes; rodar em paralelo evita esperar
    // dois round-trips em série.
    await Future.wait([
      _safeInit(
        'GoogleAuthProvider',
        () => service_locator.getIt<GoogleAuthProvider>().initialize(),
      ),
      _safeInit(
        'DropboxAuthProvider',
        () => service_locator.getIt<DropboxAuthProvider>().initialize(),
        logLevel: _LogLevel.debug,
      ),
    ]);
  }

  static Future<void> _safeInit(
    String name,
    Future<void> Function() init, {
    _LogLevel logLevel = _LogLevel.warning,
  }) async {
    try {
      await init();
      LoggerService.info('$name inicializado');
    } on Object catch (e, s) {
      switch (logLevel) {
        case _LogLevel.debug:
          LoggerService.debug('Erro ao inicializar $name: $e');
        case _LogLevel.warning:
          LoggerService.warning('Erro ao inicializar $name: $e', e, s);
      }
    }
  }

  static Future<void> _initializeAutoUpdate({required AppMode appMode}) async {
    try {
      final features = service_locator.getIt<FeatureAvailabilityService>();
      if (!features.isAutoUpdateEnabled) {
        LoggerService.info(
          'AutoUpdateService omitido (compatibilidade): '
          '${features.autoUpdateDisabledReason?.diagnosticLabel ?? "unknown"}',
        );
        return;
      }
      final autoUpdateService = service_locator.getIt<AutoUpdateService>();
      autoUpdateService.installContextProvider = (release) async {
        return AppUpdateInstallContext(
          origin: AppUpdateLaunchOrigin.ui,
          appMode: appMode,
          currentVersion: autoUpdateService.snapshot.currentVersion ?? '0.0.0',
          targetVersion: release.targetVersion,
          relaunchArguments: List<String>.of(Platform.executableArguments),
          executablePath: Platform.resolvedExecutable,
          createdAt: DateTime.now(),
        );
      };
      autoUpdateService.installReadinessCheck = (release, source) {
        // §audit-2026-05-28: antes so checavamos `BackupProgressProvider`
        // (backup LOCAL na UI), mas em modo cliente o backup roda no
        // SERVIDOR e o que o cliente vê é uma execução remota +
        // transferência de arquivo. Sem essas checagens, o update podia
        // iniciar no meio de um download de 5 GB derrubando o handoff.
        //
        // §audit-2026-05-28 wave 4: adicionada checagem de UAC — auto-update
        // **automático** (periodic/startup) que dispararia prompt UAC
        // visível ao usuário interativo é bloqueado e devolve mensagem
        // pedindo update manual. Manual passa pelo mesmo readiness mas
        // SEM o gate de UAC — operador sabe que vai aparecer o prompt.
        return checkInstallReadiness(
          getIt: service_locator.getIt,
          source: source,
        );
      };
      autoUpdateService.beforeInstallHook = AppCleanup.cleanup;
      await autoUpdateService.initialize();
      if (!autoUpdateService.isInitialized) {
        LoggerService.info(
          'AutoUpdateService inicializado em modo desabilitado/sem feed',
        );
        return;
      }
      autoUpdateService.startPeriodicChecks();
      unawaited(
        autoUpdateService.checkNow(source: AppUpdateSource.startup),
      );
      LoggerService.info('AutoUpdateService pronto');
    } on Object catch (e) {
      LoggerService.warning('Erro ao inicializar AutoUpdateService: $e');
    }
  }

  static Future<LaunchConfig> getLaunchConfig({
    required LaunchBootstrapContext bootstrapContext,
  }) async {
    final startMinimizedFromSettings = await service_locator
        .getIt<IMachineSettingsRepository>()
        .getStartMinimized();
    LoggerService.info(
      'Configuração "Iniciar minimizado" carregada: '
      '$startMinimizedFromSettings',
    );

    final args = bootstrapContext.rawArgs;
    final startMinimizedFromArgs = bootstrapContext.startMinimizedFromArgs;
    LoggerService.info(
      'Argumentos de linha de comando (via bootstrapContext): $args '
      '(${SingleInstanceConfig.minimizedArgument}: $startMinimizedFromArgs)',
    );

    final scheduleId = ScheduleArgs.extract(args);
    final startMinimized = startMinimizedFromArgs || startMinimizedFromSettings;

    LoggerService.info(
      'Iniciar minimizado: $startMinimized '
      '(configuração: $startMinimizedFromSettings, argumento: '
      '$startMinimizedFromArgs)',
    );

    return LaunchConfig(
      scheduleId: scheduleId,
      startMinimized: startMinimized,
      args: args,
    );
  }
}

class LaunchConfig {
  const LaunchConfig({
    required this.scheduleId,
    required this.startMinimized,
    required this.args,
  });

  final String? scheduleId;
  final bool startMinimized;
  final List<String> args;
}

enum _LogLevel { debug, warning }

/// Returns a non-null [AppUpdateBlockOutcome] when ANY long-running task
/// that would be disrupted by an in-place app update is currently active:
///
/// 1. **Local backup running in the UI** (`BackupProgressProvider`).
/// 2. **Remote backup executing on the server** (`RemoteSchedulesProvider`)
///    — case central no modo cliente, onde o backup é sempre remoto.
/// 3. **File transfer from server → client** (`RemoteFileTransferProvider`)
///    — downloads de várias dezenas de MB/GB que não podem ser
///    interrompidos por um relaunch silencioso.
/// 4. **UAC prompt iminente** (`IElevationProbe`) — quando o SO vai
///    disparar prompt UAC e o usuário **não está pedindo** o update
///    (origem `periodic`/`startup`). Auto-update silencioso aqui só
///    consegue ser confirmado se o usuário estiver olhando para a
///    tela; senão, ele clica "Não" por reflexo e o handoff falha
///    sem que ninguém entenda por quê.
///
/// Returns `null` quando o app está pronto para o handoff de update.
///
/// Encapsulado como função top-level (em vez de método estático privado)
/// para permitir teste unitário com um `GetIt` isolado.
@visibleForTesting
Future<AppUpdateBlockOutcome?> checkInstallReadiness({
  required GetIt getIt,
  AppUpdateSource source = AppUpdateSource.manual,
}) async {
  try {
    if (getIt.isRegistered<BackupProgressProvider>()) {
      final backupProgress = getIt<BackupProgressProvider>();
      if (backupProgress.isRunning) {
        final backupName = backupProgress.currentBackupName;
        return AppUpdateBlockOutcome(
          reason: AppUpdateBlockReason.localBackupRunning,
          message: backupName == null
              ? 'Atualização bloqueada: existe um backup em andamento na UI. '
                    'Aguarde a conclusão e tente novamente.'
              : 'Atualização bloqueada: o backup "$backupName" ainda está em '
                    'execução. Aguarde a conclusão e tente novamente.',
        );
      }
    }
    if (getIt.isRegistered<RemoteSchedulesProvider>()) {
      final remote = getIt<RemoteSchedulesProvider>();
      if (remote.isExecuting) {
        return const AppUpdateBlockOutcome(
          reason: AppUpdateBlockReason.remoteBackupRunning,
          message:
              'Atualização bloqueada: existe um backup remoto em '
              'execução. Aguarde a conclusão e tente novamente.',
        );
      }
    }
    if (getIt.isRegistered<RemoteFileTransferProvider>()) {
      final transfer = getIt<RemoteFileTransferProvider>();
      if (transfer.isTransferring) {
        return const AppUpdateBlockOutcome(
          reason: AppUpdateBlockReason.fileTransferActive,
          message:
              'Atualização bloqueada: existe uma transferência de '
              'arquivo do servidor em andamento. Aguarde a conclusão '
              'e tente novamente.',
        );
      }
    }
    // §audit-2026-05-28 wave 4: gate UAC. Só vale para checagens
    // **automáticas** — `manual` significa o usuário clicou
    // "Atualizar agora" e está pronto para o prompt UAC.
    if (source != AppUpdateSource.manual &&
        getIt.isRegistered<IElevationProbe>()) {
      final probe = getIt<IElevationProbe>();
      final snapshot = await probe.probe();
      if (snapshot.wouldTriggerUacPrompt) {
        LoggerService.info(
          '[auto-update] silencioso bloqueado: UAC ativo + processo '
          'não-elevado (source=${source.name}). Operador deve iniciar '
          'manualmente.',
        );
        return const AppUpdateBlockOutcome(
          reason: AppUpdateBlockReason.uacPolicy,
          message:
              'Atualização automática pausada: o Windows pediria '
              'aprovação UAC para instalar a nova versão. Abra '
              '"Atualizações" no app e use "Atualizar agora" para '
              'autorizar manualmente.',
        );
      }
    }
    return null;
  } on Object catch (e) {
    // Falha de leitura desses providers NÃO deve bloquear o update —
    // pior cenário: deixamos passar uma transferência em curso.
    // Logamos e seguimos com o caminho normal.
    LoggerService.warning(
      'Erro ao checar prontidão remota para auto-update: $e',
    );
    return null;
  }
}
