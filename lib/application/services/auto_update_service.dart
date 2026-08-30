import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/auto_update/app_update_artifact_store.dart';
import 'package:backup_database/application/services/auto_update/app_update_decision_engine.dart';
import 'package:backup_database/application/services/auto_update/app_update_diagnostics_store.dart';
import 'package:backup_database/application/services/auto_update/app_update_global_lock.dart';
import 'package:backup_database/application/services/auto_update/app_update_install_context_store.dart';
import 'package:backup_database/application/services/auto_update/app_update_installer_launcher.dart';
import 'package:backup_database/application/services/auto_update/app_update_types.dart';
import 'package:backup_database/application/services/auto_update/appcast_parser.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/exit_codes.dart';
import 'package:backup_database/core/service/service_shutdown_handler.dart';
import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:backup_database/core/utils/service_mode_detector.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

export 'package:backup_database/application/services/auto_update/app_update_types.dart';

class AutoUpdateService {
  AutoUpdateService({
    Dio? dio,
    PackageInfoLoader? packageInfoLoader,
    FeedUrlReader? feedUrlReader,
    CheckIntervalReader? checkIntervalReader,
    DirectoryResolver? locksDirectoryResolver,
    DirectoryResolver? updatesDirectoryResolver,
    DetachedProcessStarter? detachedProcessStarter,
    ExitProcess? exitProcess,
    FreeDiskSpaceProbe? freeDiskSpaceProbe,
    ProcessAliveCheck? processAliveCheck,
    MachineIdResolver? machineIdResolver,
    @visibleForTesting Duration? beforeInstallHookTimeout,
    @visibleForTesting Duration? installerSpawnGracePeriod,
  }) : _dio = dio ?? Dio(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _feedUrlReader =
           feedUrlReader ?? (() => dotenv.env['AUTO_UPDATE_FEED_URL']),
       _checkIntervalReader =
           checkIntervalReader ?? (() => dotenv.env[checkIntervalEnvVar]),
       _locksDirectoryResolver =
           locksDirectoryResolver ?? resolveMachineLocksDirectory,
       _updatesDirectoryResolver =
           updatesDirectoryResolver ?? resolveMachineUpdateDownloadsDirectory,
       _detachedProcessStarter =
           detachedProcessStarter ?? _defaultDetachedProcessStarter,
       _exitProcess = exitProcess ?? exit,
       _freeDiskSpaceProbe = freeDiskSpaceProbe ?? _defaultFreeDiskSpaceProbe,
       _processAliveCheck =
           processAliveCheck ?? AppUpdateGlobalLock.defaultProcessAliveCheck,
       _machineIdResolver = machineIdResolver ?? _defaultMachineIdResolver,
       _beforeInstallHookTimeoutOverride = beforeInstallHookTimeout,
       _installerSpawnGracePeriodOverride = installerSpawnGracePeriod {
    _applyDefaultNetworkTimeouts(_dio);
    _installerLauncher = AppUpdateInstallerLauncher(
      detachedProcessStarter: _detachedProcessStarter,
      processAliveCheck: _processAliveCheck,
      spawnGracePeriod: _installerSpawnGracePeriod,
    );
    _diagnosticsStore = AppUpdateDiagnosticsStore(
      updatesDirectoryResolver: _updatesDirectoryResolver,
    );
    _installContextStore = AppUpdateInstallContextStore(
      updatesDirectoryResolver: _updatesDirectoryResolver,
    );
    _artifactStore = AppUpdateArtifactStore(
      dio: _dio,
      updatesDirectoryResolver: _updatesDirectoryResolver,
      freeDiskSpaceProbe: _freeDiskSpaceProbe,
      runWithRetry: _runWithRetry,
      installContextStore: _installContextStore,
      diagnosticsStore: _diagnosticsStore,
    );
    _globalLock = AppUpdateGlobalLock(
      locksDirectoryResolver: _locksDirectoryResolver,
      processAliveCheck: _processAliveCheck,
    );
  }

  static const int defaultCheckIntervalSeconds = 3600;

  /// Nome da variavel de ambiente (lida via dotenv) para sobrescrever o
  /// intervalo periodico. Valor `0` desativa o timer periodico (so on-demand).
  /// Outros valores positivos sao tratados como segundos (>=60).
  static const String checkIntervalEnvVar =
      'AUTO_UPDATE_CHECK_INTERVAL_SECONDS';

  /// Timeout do `beforeInstallHook` em modo UI (cleanup de backups locais).
  @visibleForTesting
  static const Duration beforeInstallHookTimeoutUi = Duration(seconds: 90);

  /// Janela curta para confirmar que o instalador silencioso realmente
  /// iniciou (pid vivo pelo menos uma vez dentro da janela).
  static const Duration _defaultInstallerSpawnGracePeriod = Duration(
    seconds: 5,
  );

  /// Espera curta antes do `exit()` para o S.O. registrar o spawn detached.
  static const Duration _exitGracePeriod = Duration(milliseconds: 250);

  /// Argumentos do Inno Setup para auto-update silencioso.
  ///
  /// `/MODE=` preserva server vs client no wizard customizado, que o Inno
  /// nao restaura via `UsePreviousTasks`. `unified` cai em `server`.
  @visibleForTesting
  static List<String> installerArgumentsFor(AppMode mode) =>
      AppUpdateInstallerLauncher.installerArgumentsFor(mode);

  static const Duration defaultLockStaleAfter =
      AppUpdateConstants.defaultLockStaleAfter;
  @visibleForTesting
  static const int updateContextSchemaVersion =
      AppUpdateConstants.updateContextSchemaVersion;
  @visibleForTesting
  static const Duration updateContextTtl = AppUpdateConstants.updateContextTtl;

  /// Versao do schema usada nas linhas de `auto_update_history.jsonl`.
  /// Linhas sem `schemaVersion` (legado) sao mantidas; linhas com
  /// `schemaVersion` desconhecida sao descartadas durante a rotacao.
  @visibleForTesting
  static const int diagnosticsSchemaVersion =
      AppUpdateConstants.diagnosticsSchemaVersion;

  static const Duration _defaultNetworkTimeout = Duration(seconds: 30);
  static const int _maxNetworkAttempts = 3;
  static const Duration _initialRetryDelay = Duration(milliseconds: 500);
  static final Version _fallbackVersion = Version(0, 0, 0);

  final Dio _dio;
  final PackageInfoLoader _packageInfoLoader;
  final FeedUrlReader _feedUrlReader;
  final CheckIntervalReader _checkIntervalReader;
  final DirectoryResolver _locksDirectoryResolver;
  final DirectoryResolver _updatesDirectoryResolver;
  final DetachedProcessStarter _detachedProcessStarter;
  final ExitProcess _exitProcess;
  final FreeDiskSpaceProbe _freeDiskSpaceProbe;
  final ProcessAliveCheck _processAliveCheck;
  final MachineIdResolver _machineIdResolver;
  final Duration? _beforeInstallHookTimeoutOverride;
  final Duration? _installerSpawnGracePeriodOverride;

  late final AppUpdateInstallerLauncher _installerLauncher;
  late final AppUpdateDiagnosticsStore _diagnosticsStore;
  late final AppUpdateInstallContextStore _installContextStore;
  late final AppUpdateArtifactStore _artifactStore;
  late final AppUpdateGlobalLock _globalLock;

  Duration get _beforeInstallHookTimeout =>
      _beforeInstallHookTimeoutOverride ??
      (ServiceModeDetector.isServiceMode()
          ? ServiceShutdownHandler.defaultGracefulShutdownTimeout
          : beforeInstallHookTimeoutUi);

  Duration get _installerSpawnGracePeriod =>
      _installerSpawnGracePeriodOverride ?? _defaultInstallerSpawnGracePeriod;

  final StreamController<AppUpdateSnapshot> _snapshotController =
      StreamController<AppUpdateSnapshot>.broadcast();

  Timer? _periodicTimer;
  Future<void>? _activeCheck;
  int _checkAttemptCounter = 0;
  bool _isInitialized = false;
  String? _feedUrl;
  BeforeInstallHook? beforeInstallHook;
  InstallReadinessCheck? installReadinessCheck;
  UpdateInstallContextProvider? installContextProvider;
  AppUpdateSnapshot _snapshot = const AppUpdateSnapshot(
    status: AppUpdateStatus.idle,
  );

  Stream<AppUpdateSnapshot> get snapshots => _snapshotController.stream;
  AppUpdateSnapshot get snapshot => _snapshot;
  bool get isInitialized =>
      _isInitialized && _snapshot.status != AppUpdateStatus.disabled;
  String? get feedUrl => _feedUrl;

  static String machineRootSupportPath({
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final programData = env['ProgramData'] ?? r'C:\ProgramData';
    return p.join(programData, 'BackupDatabase');
  }

  static String updateContextSupportPath({Map<String, String>? environment}) {
    return p.join(
      machineRootSupportPath(environment: environment),
      MachineStorageLayout.staging,
      MachineStorageLayout.updates,
      AppUpdateConstants.updateContextFileName,
    );
  }

  static String diagnosticsSupportPath({Map<String, String>? environment}) {
    return p.join(
      machineRootSupportPath(environment: environment),
      MachineStorageLayout.staging,
      MachineStorageLayout.updates,
      AppUpdateConstants.updateDiagnosticsFileName,
    );
  }

  static String lockFileSupportPath({Map<String, String>? environment}) {
    return p.join(
      machineRootSupportPath(environment: environment),
      MachineStorageLayout.locks,
      AppUpdateConstants.lockFileName,
    );
  }

  /// Caminho do arquivo `.env` que o updater espera consumir (apenas
  /// para diagnóstico na UI / mensagens corretivas). Não é uma garantia
  /// de qual `.env` foi efetivamente carregado em runtime — esse dado
  /// vem do `EnvironmentLoader.outcome`.
  static String configFileSupportPath({Map<String, String>? environment}) {
    return p.join(
      machineRootSupportPath(environment: environment),
      MachineStorageLayout.config,
      '.env',
    );
  }

  /// Emite log estruturado de fase do auto-update para correlação nos
  /// arquivos `logs/app_YYYY-MM-DD.log`. Pattern alinhado com
  /// `[main] bootstrap_timing phase=...` (audit 2026-05-28 — antes só
  /// havia logs ad-hoc).
  static void _logPhase(
    String phase, {
    Map<String, Object?> data = const {},
  }) {
    final parts = data.entries.map((e) => '${e.key}=${e.value}').join(' ');
    LoggerService.info(
      '[auto-update] phase=$phase${parts.isEmpty ? '' : ' $parts'}',
    );
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      LoggerService.warning('AutoUpdateService ja foi inicializado');
      return;
    }
    _logPhase('initialize_begin');

    final currentVersion = await _resolveCurrentVersion();
    _logPhase(
      'initialize_version_resolved',
      data: {
        'currentVersion': currentVersion,
      },
    );

    // §audit-2026-05-28: o reader pode lançar `NotInitializedError`
    // quando o `dotenv` falhou no boot. Antes a exceção subia para o
    // `_initializeAutoUpdate` que apenas logava warning, deixando o
    // snapshot em `idle` silenciosamente. Agora capturamos e emitimos
    // snapshot `disabled` com `disabledReason=feedReaderException` —
    // a UI mostra mensagem técnica copiável em vez de "ready".
    String? configuredFeedUrl;
    Object? readerError;
    try {
      configuredFeedUrl = _feedUrlReader()?.trim();
    } on Object catch (e, s) {
      readerError = e;
      LoggerService.error(
        'AutoUpdateService: feedUrlReader lancou excecao (provavel '
        'dotenv nao inicializado): $e',
        e,
        s,
      );
    }

    _isInitialized = true;
    _feedUrl = configuredFeedUrl != null && configuredFeedUrl.isNotEmpty
        ? configuredFeedUrl
        : null;

    await _cleanupInitialArtifacts();

    if (!Platform.isWindows) {
      _emitSnapshot(
        AppUpdateSnapshot(
          status: AppUpdateStatus.disabled,
          currentVersion: currentVersion.toString(),
          stage: AppUpdateStage.completed,
          message: 'Atualizacoes automaticas disponiveis apenas no Windows.',
          disabledReason: AppUpdateDisabledReason.nonWindowsPlatform,
        ),
      );
      _logPhase(
        'initialize_done',
        data: {
          'status': 'disabled',
          'reason': 'non_windows_platform',
        },
      );
      return;
    }

    if (readerError != null) {
      _emitSnapshot(
        AppUpdateSnapshot(
          status: AppUpdateStatus.disabled,
          currentVersion: currentVersion.toString(),
          stage: AppUpdateStage.completed,
          message:
              'Configuracao indisponivel: falha ao ler AUTO_UPDATE_FEED_URL '
              'do dotenv ($readerError).',
          errorMessage: readerError.toString(),
          disabledReason: AppUpdateDisabledReason.feedReaderException,
        ),
      );
      _logPhase(
        'initialize_done',
        data: {
          'status': 'disabled',
          'reason': 'feed_reader_exception',
          'error': readerError.runtimeType,
        },
      );
      return;
    }

    if (_feedUrl == null) {
      _emitSnapshot(
        AppUpdateSnapshot(
          status: AppUpdateStatus.disabled,
          currentVersion: currentVersion.toString(),
          stage: AppUpdateStage.completed,
          message:
              'AUTO_UPDATE_FEED_URL nao configurada em '
              r'C:\ProgramData\BackupDatabase\config\.env.',
          disabledReason: AppUpdateDisabledReason.feedUrlMissing,
        ),
      );
      _logPhase(
        'initialize_done',
        data: {
          'status': 'disabled',
          'reason': 'feed_url_missing',
        },
      );
      return;
    }

    _emitSnapshot(
      AppUpdateSnapshot(
        status: AppUpdateStatus.idle,
        currentVersion: currentVersion.toString(),
        feedUrl: _feedUrl,
        stage: AppUpdateStage.completed,
        message: 'Atualizador pronto para verificar novas versoes.',
      ),
    );

    _logPhase(
      'initialize_done',
      data: {
        'status': 'idle',
        'feedUrlLength': _feedUrl!.length,
      },
    );
  }

  Future<void> _cleanupInitialArtifacts() async {
    try {
      await _cleanupStaleUpdateArtifacts();
      await _cleanupStagedInstallers();
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao limpar artefatos de staging/diagnostico na inicializacao',
        e,
        s,
      );
    }
  }

  void startPeriodicChecks({
    Duration interval = const Duration(seconds: defaultCheckIntervalSeconds),
  }) {
    if (!isInitialized) {
      LoggerService.info(
        'AutoUpdateService: verificacoes periodicas ignoradas '
        '(servico indisponivel)',
      );
      return;
    }

    final overridden = _resolveOverriddenInterval(interval);
    if (overridden == null) {
      _periodicTimer?.cancel();
      _periodicTimer = null;
      LoggerService.info(
        'AutoUpdateService: verificacoes periodicas DESATIVADAS '
        '(via $checkIntervalEnvVar=0). Apenas execucoes manuais ou de startup.',
      );
      return;
    }

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(overridden, (_) {
      unawaited(checkNow(source: AppUpdateSource.periodic));
    });

    LoggerService.info(
      'AutoUpdateService: verificacoes periodicas configuradas em '
      '${overridden.inSeconds}s',
    );
  }

  /// Calcula o intervalo efetivo aplicando `AUTO_UPDATE_CHECK_INTERVAL_SECONDS`.
  /// Retorna `null` quando o operador pediu para desativar o timer (valor `0`).
  /// Valores invalidos ou menores que 60 caem no `defaultInterval`.
  Duration? _resolveOverriddenInterval(Duration defaultInterval) {
    final raw = _checkIntervalReader()?.trim();
    if (raw == null || raw.isEmpty) {
      return defaultInterval;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      LoggerService.warning(
        'AutoUpdateService: $checkIntervalEnvVar="$raw" nao e numero; '
        'mantendo padrao (${defaultInterval.inSeconds}s).',
      );
      return defaultInterval;
    }
    if (parsed == 0) {
      return null;
    }
    if (parsed < 60) {
      LoggerService.warning(
        'AutoUpdateService: $checkIntervalEnvVar=$parsed < 60s nao e '
        'permitido (evita pressao no feed); aplicando 60s.',
      );
      return const Duration(seconds: 60);
    }
    return Duration(seconds: parsed);
  }

  Future<void> checkNow({required AppUpdateSource source}) async {
    if (_activeCheck != null) {
      LoggerService.info(
        'AutoUpdateService: verificacao ja em andamento, aguardando resultado',
      );
      return _activeCheck;
    }

    return _activeCheck = _runCheck(source).whenComplete(() {
      _activeCheck = null;
    });
  }

  void clearError() {
    if (_snapshot.errorMessage == null) {
      return;
    }

    final fallbackStatus = _feedUrl == null
        ? AppUpdateStatus.disabled
        : AppUpdateStatus.idle;
    _emitSnapshot(
      _snapshot.copyWith(
        status: fallbackStatus,
        errorMessage: null,
        message: 'Erro limpo. Aguardando nova verificacao.',
      ),
    );
  }

  Future<void> dispose() async {
    _periodicTimer?.cancel();
    await _snapshotController.close();
  }

  /// Fachada `@visibleForTesting` que delega para [AppcastParser.parse].
  /// Mantida aqui para preservar os ~10 testes existentes em
  /// `auto_update_service_test.dart` que chamam `AutoUpdateService.parseAppcast`.
  /// Novo código deve usar `AppcastParser.parse` direto.
  @visibleForTesting
  static List<AppcastRelease> parseAppcast(String xmlContent) =>
      AppcastParser.parse(xmlContent);

  /// Fachada `@visibleForTesting` que delega para
  /// [AppUpdateDecisionEngine.evaluate]. Mantida aqui para preservar
  /// os testes existentes em `auto_update_service_test.dart` que
  /// chamam `AutoUpdateService.evaluateRelease`. Novo código deve usar
  /// `AppUpdateDecisionEngine.evaluate` direto.
  @visibleForTesting
  static AppUpdateDecision evaluateRelease({
    required List<AppcastRelease> releases,
    required Version currentVersion,
    String? machineId,
  }) {
    return AppUpdateDecisionEngine.evaluate(
      releases: releases,
      currentVersion: currentVersion,
      machineId: machineId,
    );
  }

  @visibleForTesting
  static Future<void> validateDownloadedInstaller(
    File installer,
    AppcastRelease release,
  ) async {
    final fileLength = await installer.length();
    if (fileLength != release.fileSizeBytes) {
      throw StateError(
        'Tamanho do instalador invalido. Esperado ${release.fileSizeBytes} '
        'bytes, obtido $fileLength bytes.',
      );
    }

    final computedHash = await FileHashUtils.computeSha256(installer);
    if (computedHash.toLowerCase() != release.sha256.toLowerCase()) {
      throw StateError(
        'SHA-256 invalido para ${installer.path}. Esperado ${release.sha256}, '
        'obtido $computedHash.',
      );
    }
  }

  Future<void> _runCheck(AppUpdateSource source) async {
    if (!isInitialized) {
      LoggerService.info(
        'AutoUpdateService: checkNow ignorado (servico indisponivel)',
      );
      return;
    }

    final attemptNumber = ++_checkAttemptCounter;
    final checkStopwatch = Stopwatch()..start();
    Duration? downloadDuration;
    var currentStage = AppUpdateStage.fetchingFeed;
    final now = DateTime.now();
    final currentVersion = await _resolveCurrentVersion();
    String? targetVersion;
    var handoffExitInvoked = false;
    var installerSpawnConfirmed = false;
    int? installerBytes;
    AppUpdateInstallContext? installContext;

    final lockHandle = await _tryAcquireLock(
      source: source,
      currentVersion: currentVersion.toString(),
      attemptNumber: attemptNumber,
    );

    // Helper local: muda `currentStage` (lido pelo catch global para
    // logar onde a falha aconteceu) e atualiza o metadata do lock no
    // disco. Antes este pattern aparecia inline ~9 vezes no pipeline.
    Future<void> transitionStage(
      AppUpdateStage stage, {
      Map<String, String?> extraMetadata = const <String, String?>{},
    }) async {
      currentStage = stage;
      await lockHandle?.updateMetadata({
        'stage': _stageToken(stage),
        ...extraMetadata,
      });
    }

    if (lockHandle == null) {
      _logTelemetry(
        'lock ocupado por outra instancia',
        source: source,
        attemptNumber: attemptNumber,
        stage: AppUpdateStage.blockedByOtherInstance,
      );
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.blockedByOtherInstance,
          stage: AppUpdateStage.blockedByOtherInstance,
          message:
              'Outra instancia da aplicacao ja esta processando a atualizacao.',
          errorMessage: null,
          lastSource: source,
          lastAttemptNumber: attemptNumber,
          lastCheckAt: now,
        ),
      );
      await _persistDiagnostics(
        source: source,
        attemptNumber: attemptNumber,
        currentVersion: currentVersion.toString(),
        stage: AppUpdateStage.blockedByOtherInstance,
        status: AppUpdateStatus.blockedByOtherInstance,
        startedAt: now,
        duration: checkStopwatch.elapsed,
      );
      return;
    }

    try {
      _logTelemetry(
        'iniciando ciclo de verificacao',
        source: source,
        attemptNumber: attemptNumber,
        stage: currentStage,
        currentVersion: currentVersion.toString(),
      );
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.checking,
          currentVersion: currentVersion.toString(),
          feedUrl: _feedUrl,
          release: null,
          stage: currentStage,
          message: 'Verificando novas versoes no feed configurado...',
          errorMessage: null,
          lastSource: source,
          lastAttemptNumber: attemptNumber,
          lastFailureStage: null,
        ),
      );

      final releases = await _fetchReleases();
      await transitionStage(AppUpdateStage.evaluatingRelease);
      final machineId = await _safeResolveMachineId();
      final decision = AppUpdateDecisionEngine.evaluate(
        releases: releases,
        currentVersion: currentVersion,
        machineId: machineId,
      );

      if (!decision.isUpdateAvailable) {
        checkStopwatch.stop();
        await transitionStage(AppUpdateStage.completed);
        _logTelemetry(
          'nenhuma atualizacao disponivel',
          source: source,
          attemptNumber: attemptNumber,
          stage: AppUpdateStage.completed,
          currentVersion: currentVersion.toString(),
          totalDuration: checkStopwatch.elapsed,
        );
        _emitSnapshot(
          _snapshot.copyWith(
            status: AppUpdateStatus.upToDate,
            currentVersion: currentVersion.toString(),
            release: null,
            stage: AppUpdateStage.completed,
            message: 'Aplicacao ja esta na versao mais recente.',
            errorMessage: null,
            lastCheckAt: now,
            lastSource: source,
            lastAttemptNumber: attemptNumber,
            lastCheckDuration: checkStopwatch.elapsed,
          ),
        );
        await _persistDiagnostics(
          source: source,
          attemptNumber: attemptNumber,
          currentVersion: currentVersion.toString(),
          stage: AppUpdateStage.completed,
          status: AppUpdateStatus.upToDate,
          startedAt: now,
          duration: checkStopwatch.elapsed,
        );
        return;
      }

      final release = decision.latestRelease!;
      targetVersion = release.targetVersion;
      await transitionStage(
        AppUpdateStage.evaluatingRelease,
        extraMetadata: {'targetVersion': release.targetVersion},
      );

      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.updateAvailable,
          currentVersion: currentVersion.toString(),
          release: release,
          stage: AppUpdateStage.evaluatingRelease,
          message:
              'Nova versao ${release.targetVersion} encontrada. '
              'Iniciando download silencioso.',
          errorMessage: null,
          lastCheckAt: now,
          lastSource: source,
          lastAttemptNumber: attemptNumber,
        ),
      );

      await transitionStage(AppUpdateStage.downloadingInstaller);
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.downloading,
          release: release,
          stage: currentStage,
          message:
              'Baixando instalador ${release.installerFileName} para staging...',
        ),
      );

      final downloadStopwatch = Stopwatch()..start();
      final installer = await _downloadInstaller(release);
      downloadStopwatch.stop();
      downloadDuration = downloadStopwatch.elapsed;
      installerBytes = await installer.length();
      _logTelemetry(
        'download do instalador concluido',
        source: source,
        attemptNumber: attemptNumber,
        stage: currentStage,
        targetVersion: release.targetVersion,
        totalDuration: downloadDuration,
        installerBytes: installerBytes,
        downloadDuration: downloadDuration,
      );

      await transitionStage(AppUpdateStage.validatingInstaller);
      await validateDownloadedInstaller(installer, release);

      await transitionStage(AppUpdateStage.preparingInstall);
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.downloading,
          release: release,
          stage: currentStage,
          lastDownloadDuration: downloadDuration,
          message:
              'Instalador validado. Preparando troca silenciosa para '
              '${release.targetVersion}.',
        ),
      );

      final blockOutcome = await installReadinessCheck?.call(release, source);
      if (blockOutcome != null) {
        throw AppUpdateBlockedException(
          message: blockOutcome.message,
          status: AppUpdateStatus.blockedByActiveBackup,
          stage: AppUpdateStage.blockedByActiveBackup,
          reason: blockOutcome.reason,
        );
      }

      if (beforeInstallHook != null) {
        final hookTimeout = _beforeInstallHookTimeout;
        try {
          await beforeInstallHook!.call().timeout(
            hookTimeout,
            onTimeout: () {
              throw BeforeInstallHookTimeoutException(hookTimeout);
            },
          );
        } on BeforeInstallHookTimeoutException {
          rethrow;
        } on TimeoutException {
          throw BeforeInstallHookTimeoutException(hookTimeout);
        }
      }

      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.installing,
          release: release,
          stage: currentStage,
          lastDownloadDuration: downloadDuration,
          message:
              'Preparacao concluida. Iniciando troca silenciosa para '
              '${release.targetVersion}.',
        ),
      );

      installContext = await _persistInstallContext(
        release: release,
        currentVersion: currentVersion.toString(),
      );

      await transitionStage(AppUpdateStage.launchingInstaller);

      final spawnHandle = await _launchInstaller(
        installer,
        mode: installContext.appMode,
      );
      final spawnAlive = await _waitForInstallerSpawn(spawnHandle);
      if (!spawnAlive) {
        // O processo do instalador morreu antes da janela de graca. Pode
        // ser UAC negado (modo UI nao admin), antivirus bloqueando, ou
        // Inno Setup falhando no preflight. Nao podemos chamar exit aqui
        // — manter UI/servico vivo para o operador investigar/reagir.
        throw StateError(
          'Instalador encerrou imediatamente apos o spawn '
          '(pid=${spawnHandle?.pid ?? "desconhecido"}). '
          'Possiveis causas: UAC negado, antivirus bloqueando, '
          'instalador corrompido. Verifique o log do Inno Setup em '
          r'%TEMP%\Setup Log*.txt.',
        );
      }
      installerSpawnConfirmed = true;

      checkStopwatch.stop();
      await transitionStage(AppUpdateStage.completed);
      _logTelemetry(
        'instalador silencioso iniciado',
        source: source,
        attemptNumber: attemptNumber,
        stage: currentStage,
        targetVersion: release.targetVersion,
        totalDuration: checkStopwatch.elapsed,
        installerBytes: installerBytes,
        downloadDuration: downloadDuration,
      );
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.handoffCompleted,
          release: release,
          stage: AppUpdateStage.completed,
          lastDownloadDuration: downloadDuration,
          lastCheckDuration: checkStopwatch.elapsed,
          message:
              'Instalador iniciado em background. Encerrando processo atual...',
        ),
      );

      await _persistDiagnostics(
        source: source,
        attemptNumber: attemptNumber,
        currentVersion: currentVersion.toString(),
        targetVersion: release.targetVersion,
        stage: AppUpdateStage.completed,
        status: AppUpdateStatus.handoffCompleted,
        startedAt: now,
        duration: checkStopwatch.elapsed,
        installerBytes: installerBytes,
        downloadDuration: downloadDuration,
      );
      // Mantem o lock global ate o processo encerrar — evita que outra
      // instancia inicie um segundo handoff durante a janela do setup.
      handoffExitInvoked = true;
      await Future<void>.delayed(_exitGracePeriod);

      // Exit code dinamico: em modo servico usamos `handoffForInstaller (78)`
      // para impedir NSSM AppExit Default Restart durante a janela do setup.
      // Em modo UI nao ha NSSM envolvido, `success (0)` basta.
      final exitCode = installContext.origin == AppUpdateLaunchOrigin.service
          ? ServiceModeExitCode.handoffForInstaller
          : UiBootstrapExitCode.success;
      _exitProcess(exitCode);
    } on AppUpdateBlockedException catch (e) {
      if (checkStopwatch.isRunning) {
        checkStopwatch.stop();
      }
      LoggerService.warning(
        'Auto update bloqueado antes da instalacao: ${e.message}',
      );
      await transitionStage(e.stage);
      _emitSnapshot(
        _snapshot.copyWith(
          status: e.status,
          currentVersion: currentVersion.toString(),
          stage: e.stage,
          message: e.message,
          errorMessage: null,
          lastCheckAt: now,
          lastSource: source,
          lastFailureStage: e.stage,
          lastAttemptNumber: attemptNumber,
          lastDownloadDuration: downloadDuration,
          lastCheckDuration: checkStopwatch.elapsed,
          // §audit-2026-05-28 wave 4 (UI banner): propaga o motivo
          // semantico do bloqueio para a UI poder renderizar a
          // InfoBar e o botao "Atualizar agora" correto.
          blockReason: e.reason,
        ),
      );
      await _removeInstallContextOnEarlyFailure(
        e.stage,
        installerSpawnConfirmed: installerSpawnConfirmed,
      );
      await _persistDiagnostics(
        source: source,
        attemptNumber: attemptNumber,
        currentVersion: currentVersion.toString(),
        targetVersion: targetVersion,
        stage: e.stage,
        status: e.status,
        startedAt: now,
        duration: checkStopwatch.elapsed,
        installerBytes: installerBytes,
        downloadDuration: downloadDuration,
      );
    } on Object catch (e, s) {
      if (checkStopwatch.isRunning) {
        checkStopwatch.stop();
      }
      LoggerService.error(
        'Erro no pipeline de auto update '
        '(tentativa #$attemptNumber, etapa ${_stageToken(currentStage)})',
        e,
        s,
      );
      final userErrorMessage = _pipelineErrorMessage(e);
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.error,
          currentVersion: currentVersion.toString(),
          stage: currentStage,
          message: 'Falha ao processar a atualizacao automatica.',
          errorMessage: userErrorMessage,
          lastCheckAt: now,
          lastErrorAt: now,
          lastSource: source,
          lastFailureStage: currentStage,
          lastAttemptNumber: attemptNumber,
          lastDownloadDuration: downloadDuration,
          lastCheckDuration: checkStopwatch.elapsed,
        ),
      );
      await _removeInstallContextOnEarlyFailure(
        currentStage,
        installerSpawnConfirmed: installerSpawnConfirmed,
      );
      await _persistDiagnostics(
        source: source,
        attemptNumber: attemptNumber,
        currentVersion: currentVersion.toString(),
        targetVersion: targetVersion,
        stage: currentStage,
        status: AppUpdateStatus.error,
        startedAt: now,
        duration: checkStopwatch.elapsed,
        errorMessage: userErrorMessage,
        installerBytes: installerBytes,
        downloadDuration: downloadDuration,
      );
    } finally {
      if (!handoffExitInvoked) {
        await lockHandle.release();
      }
    }
  }

  Future<List<AppcastRelease>> _fetchReleases() async {
    final response = await _runWithRetry<Response<String>>(
      label: 'download do appcast',
      action: () {
        return _dio.get<String>(
          _feedUrl!,
          options: Options(responseType: ResponseType.plain),
        );
      },
    );
    final xmlContent = response.data;
    if (xmlContent == null || xmlContent.trim().isEmpty) {
      throw StateError('Feed de atualizacao vazio: $_feedUrl');
    }

    final releases = parseAppcast(xmlContent);
    if (releases.isEmpty) {
      throw StateError(
        'Feed de atualizacao sem releases validas ou sem SHA-256/length.',
      );
    }

    return releases;
  }

  Future<File> _downloadInstaller(AppcastRelease release) {
    return _artifactStore.downloadInstaller(release);
  }

  Future<DetachedProcessHandle?> _launchInstaller(
    File installer, {
    required AppMode mode,
  }) {
    return _installerLauncher.launch(installer, mode: mode);
  }

  Future<bool> _waitForInstallerSpawn(DetachedProcessHandle? handle) {
    return _installerLauncher.waitForSpawn(handle);
  }

  Future<Version> _resolveCurrentVersion() async {
    try {
      final packageInfo = await _packageInfoLoader();
      final versionString = packageInfo.buildNumber.isNotEmpty
          ? '${packageInfo.version}+${packageInfo.buildNumber}'
          : packageInfo.version;
      return _tryParseVersion(versionString) ?? _fallbackVersion;
    } on Object catch (e, s) {
      LoggerService.warning(
        'PackageInfo indisponivel para auto update; tentando APP_VERSION',
        e,
        s,
      );
      final envVersion = dotenv.env['APP_VERSION']?.trim();
      return _tryParseVersion(envVersion) ?? _fallbackVersion;
    }
  }

  @visibleForTesting
  static Future<AppUpdateLockHandle?> tryAcquireGlobalLock({
    required Directory locksDir,
    required Map<String, String?> metadata,
    Duration staleAfter = defaultLockStaleAfter,
    DateTime? now,
    ProcessAliveCheck? processAliveCheck,
  }) {
    return AppUpdateGlobalLock.tryAcquireGlobalLock(
      locksDir: locksDir,
      metadata: metadata,
      staleAfter: staleAfter,
      now: now,
      processAliveCheck: processAliveCheck,
    );
  }

  Future<AppUpdateLockHandle?> _tryAcquireLock({
    required AppUpdateSource source,
    required String currentVersion,
    required int attemptNumber,
  }) {
    return _globalLock.tryAcquire(
      source: source,
      currentVersion: currentVersion,
      attemptNumber: attemptNumber,
    );
  }

  void _emitSnapshot(AppUpdateSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }

  static Future<DetachedProcessHandle?> _defaultDetachedProcessStarter(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    );
    return DetachedProcessHandle(pid: process.pid);
  }

  /// Estimativa de espaco livre, em bytes, na particao em que `directory`
  /// reside. Retorna `null` quando nao consegue medir (ex.: plataforma nao
  /// Windows, falta de permissao). O caller trata `null` como "sem
  /// restricao" para nao bloquear o auto update em situacoes nao usuais.
  static Future<int?> _defaultFreeDiskSpaceProbe(Directory directory) async {
    if (!Platform.isWindows) {
      return null;
    }
    try {
      // PowerShell e' a forma mais simples de obter `FreeSpace` por volume sem
      // depender de FFI; o overhead (~200ms) e' irrelevante perto do download.
      final cmd =
          '(Get-PSDrive -PSProvider FileSystem -Name '
          '(Split-Path -Qualifier "${directory.path}").TrimEnd(":")).Free';
      final result = await Process.run('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        cmd,
      ]);
      if (result.exitCode != 0) {
        return null;
      }
      final raw = result.stdout.toString().trim();
      if (raw.isEmpty) {
        return null;
      }
      return int.tryParse(raw);
    } on Object {
      return null;
    }
  }

  /// Lê o MachineGuid do registro do Windows (HKLM\SOFTWARE\Microsoft\
  /// Cryptography). E' estavel entre reboots e relativamente entre
  /// reinstalacoes do Windows; ideal para staged rollout determinístico.
  /// Em qualquer falha, retorna `null` — `evaluateRelease` interpreta
  /// como "deixa passar" para nao bloquear updates por falta de dado.
  static Future<String?> _defaultMachineIdResolver() async {
    if (!Platform.isWindows) {
      return null;
    }
    try {
      final result = await Process.run('reg.exe', <String>[
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ]);
      if (result.exitCode != 0) {
        return null;
      }
      final output = result.stdout.toString();
      final match = RegExp(
        r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F\-]+)',
      ).firstMatch(output);
      return match?.group(1)?.trim();
    } on Object {
      return null;
    }
  }

  Future<AppUpdateInstallContext> _persistInstallContext({
    required AppcastRelease release,
    required String currentVersion,
  }) {
    return _installContextStore.persist(
      release: release,
      currentVersion: currentVersion,
      installContextProvider: installContextProvider,
    );
  }

  Future<void> _removeInstallContextOnEarlyFailure(
    AppUpdateStage failureStage, {
    required bool installerSpawnConfirmed,
  }) {
    return _installContextStore.removeOnEarlyFailure(
      failureStage,
      installerSpawnConfirmed: installerSpawnConfirmed,
    );
  }

  Future<void> _persistDiagnostics({
    required AppUpdateSource source,
    required int attemptNumber,
    required String currentVersion,
    required AppUpdateStage stage,
    required AppUpdateStatus status,
    required DateTime startedAt,
    required Duration duration,
    String? targetVersion,
    String? errorMessage,
    int? installerBytes,
    Duration? downloadDuration,
  }) {
    return _diagnosticsStore.persist(
      source: source,
      attemptNumber: attemptNumber,
      currentVersion: currentVersion,
      stage: stage,
      status: status,
      startedAt: startedAt,
      duration: duration,
      targetVersion: targetVersion,
      errorMessage: errorMessage,
      installerBytes: installerBytes,
      downloadDuration: downloadDuration,
    );
  }

  Future<void> _cleanupStaleUpdateArtifacts() {
    return _artifactStore.cleanupStaleUpdateArtifacts();
  }

  @visibleForTesting
  static Future<bool> isUpdateContextExpired(
    File file, {
    DateTime? now,
  }) {
    return AppUpdateInstallContextStore.isExpired(file, now: now);
  }

  @visibleForTesting
  static Future<List<String>> compactDiagnosticsLines(
    List<String> lines, {
    required DateTime now,
    Duration retention = AppUpdateDiagnosticsStore.diagnosticsRetention,
    int maxBytes = AppUpdateDiagnosticsStore.maxDiagnosticsFileBytes,
  }) {
    return AppUpdateDiagnosticsStore.compactLines(
      lines,
      now: now,
      retention: retention,
      maxBytes: maxBytes,
    );
  }

  Future<void> _cleanupStagedInstallers({String? preserveInstallerName}) {
    return _artifactStore.cleanupStagedInstallers(
      preserveInstallerName: preserveInstallerName,
    );
  }

  Future<T> _runWithRetry<T>({
    required String label,
    required Future<T> Function() action,
  }) async {
    var attempt = 0;
    var delay = _initialRetryDelay;
    while (true) {
      attempt++;
      try {
        return await action();
      } on Object catch (e, s) {
        final shouldRetry =
            attempt < _maxNetworkAttempts && _isRetryableNetworkError(e);
        if (!shouldRetry) {
          rethrow;
        }
        LoggerService.warning(
          'Falha transitoria em $label; retentando '
          '(${attempt + 1}/$_maxNetworkAttempts)',
          e,
          s,
        );
        await Future<void>.delayed(delay);
        delay = Duration(milliseconds: delay.inMilliseconds * 2);
      }
    }
  }

  static bool _isRetryableNetworkError(Object error) {
    if (error is! DioException) {
      return false;
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 0;
        return statusCode >= 500;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return false;
    }
  }

  static String _pipelineErrorMessage(Object error) {
    if (error is AppUpdateBlockedException) {
      return error.message;
    }
    if (error is StateError) {
      return error.message;
    }
    return failureUserMessage(
      error,
      fallback: 'Falha ao processar a atualizacao automatica.',
    );
  }

  static void _applyDefaultNetworkTimeouts(Dio dio) {
    dio.options = dio.options.copyWith(
      connectTimeout: dio.options.connectTimeout ?? _defaultNetworkTimeout,
      receiveTimeout: dio.options.receiveTimeout ?? _defaultNetworkTimeout,
      sendTimeout: dio.options.sendTimeout ?? _defaultNetworkTimeout,
    );
  }

  static Version? _tryParseVersion(String? raw) =>
      AppcastParser.tryParseVersion(raw);

  void _logTelemetry(
    String message, {
    required AppUpdateSource source,
    required int attemptNumber,
    required AppUpdateStage stage,
    String? currentVersion,
    String? targetVersion,
    Duration? totalDuration,
    int? installerBytes,
    Duration? downloadDuration,
  }) {
    final details = <String>[
      'tentativa=$attemptNumber',
      'origem=${source.name}',
      'etapa=${_stageToken(stage)}',
      if (currentVersion != null) 'versaoAtual=$currentVersion',
      if (targetVersion != null) 'versaoAlvo=$targetVersion',
      if (totalDuration != null) 'duracaoMs=${totalDuration.inMilliseconds}',
      if (installerBytes != null) 'bytes=$installerBytes',
      if (downloadDuration != null &&
          installerBytes != null &&
          installerBytes > 0 &&
          downloadDuration.inMilliseconds > 0)
        'downloadMbps=${_formatMbps(installerBytes, downloadDuration)}',
    ];
    LoggerService.info('AutoUpdateService: $message (${details.join(', ')})');
  }

  Future<String?> _safeResolveMachineId() async {
    try {
      return await _machineIdResolver();
    } on Object catch (e, s) {
      LoggerService.warning(
        'AutoUpdateService: falha ao obter MachineId para rollout',
        e,
        s,
      );
      return null;
    }
  }

  static String _formatMbps(int bytes, Duration duration) {
    final seconds = duration.inMilliseconds / 1000.0;
    final mbps = (bytes / (1024 * 1024)) / seconds;
    return mbps.toStringAsFixed(2);
  }

  static String _stageToken(AppUpdateStage stage) => stage.token;
}
