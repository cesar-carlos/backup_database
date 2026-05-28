import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/services/auto_update/app_update_decision_engine.dart';
import 'package:backup_database/application/services/auto_update/appcast_parser.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/exit_codes.dart';
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

enum AppUpdateSource { startup, manual, periodic }

enum AppUpdateStatus {
  idle,
  checking,
  updateAvailable,
  downloading,
  installing,
  blockedByOtherInstance,
  blockedByActiveBackup,
  handoffCompleted,
  upToDate,
  error,
  disabled,
}

/// Por que o updater entrou em estado `disabled`/`idle` sem rodar — campo
/// auxiliar de [AppUpdateSnapshot] que permite a UI mostrar mensagens
/// distintas e ações corretivas em vez de só "indisponivel neste ambiente".
///
/// Antes (audit 2026-05-28) qualquer um dos casos abaixo virava
/// `disabled+completed+null lastCheck` na UI, escondendo o motivo real.
enum AppUpdateDisabledReason {
  /// `Platform.isWindows == false`. Build é multiplataforma, mas o
  /// pipeline (Inno Setup) só roda em Windows.
  nonWindowsPlatform,

  /// `AUTO_UPDATE_FEED_URL` não está em `dotenv.env` ou veio vazio.
  /// **Acionável pelo usuário**: editar
  /// `C:\ProgramData\BackupDatabase\config\.env`.
  feedUrlMissing,

  /// `dotenv` falhou ao carregar (asset corrompido, permissão negada,
  /// etc.). **Acionável pelo dev/sysadmin**: ver logs.
  dotenvLoadFailed,

  /// `_feedUrlReader` lançou exceção (ex.: `NotInitializedError` do
  /// dotenv) — distinção semântica de [feedUrlMissing] para diagnóstico.
  feedReaderException,

  /// `FeatureAvailabilityService` desativou auto-update por
  /// incompatibilidade do SO (Server 2012/R2, OS version unresolved,
  /// etc.). UI mostra banner do `localizeCompatibilityReason`.
  osIncompatible,

  /// Exceção genérica/inesperada durante `initialize()`. UI mostra
  /// mensagem técnica copiável.
  initializationException,
}

/// Por que o updater bloqueou um ciclo de install (status
/// `blockedByActiveBackup`). Diferente de [AppUpdateDisabledReason]
/// porque o updater **está** funcional — só não pode tocar agora.
///
/// §audit-2026-05-28 wave 4 (UI banner): antes a UI mostrava o mesmo
/// texto "Ha um backup ativo" para qualquer bloqueio, mascarando
/// causas distintas (incluindo UAC, que tem ação corretiva direta).
/// Esse enum dá ao banner um caminho semântico por causa.
enum AppUpdateBlockReason {
  /// `BackupProgressProvider.isRunning` — backup local na UI.
  localBackupRunning,

  /// `RemoteSchedulesProvider.isExecuting` — backup remoto orquestrado
  /// pelo cliente. Aguardar conclusão é a única ação.
  remoteBackupRunning,

  /// `RemoteFileTransferProvider.isTransferring` — download do
  /// artefato em curso.
  fileTransferActive,

  /// UAC ativo + processo não-elevado + check `periodic`/`startup`.
  /// **Único reason com ação imediata**: clicar "Atualizar agora"
  /// (source `manual`) ignora o gate e dispara o prompt UAC visível.
  uacPolicy,

  /// Modo serviço: Windows Service rodando em conta diferente de
  /// `LocalSystem` (ver `ServiceAccountProbe`). Bloqueio permanente
  /// até reinstalar o serviço; ação manual exige reinstall.
  serviceAccountUnsupported,
}

/// Resultado tipado da checagem de readiness. Antes a função devolvia
/// só `String?`, e qualquer bloqueio virava a mesma `InfoBar` na UI.
class AppUpdateBlockOutcome {
  const AppUpdateBlockOutcome({
    required this.message,
    required this.reason,
  });

  /// Texto amigável (pt-BR) já formatado para exibir ao usuário.
  final String message;

  /// Categoria semântica do bloqueio — UI usa para escolher o tom da
  /// InfoBar, mostrar/esconder o botão "Atualizar agora", etc.
  final AppUpdateBlockReason reason;
}

enum AppUpdateStage {
  blockedByOtherInstance,
  blockedByActiveBackup,
  fetchingFeed,
  evaluatingRelease,
  downloadingInstaller,
  validatingInstaller,
  preparingInstall,
  launchingInstaller,
  completed,
}

@immutable
class AppcastRelease {
  const AppcastRelease({
    required this.version,
    required this.downloadUrl,
    required this.fileSizeBytes,
    required this.sha256,
    required this.publishedAt,
    required this.title,
    required this.description,
    this.minSupportedAppVersion,
    this.rolloutPercentage,
  });

  final Version version;
  final String downloadUrl;
  final int fileSizeBytes;
  final String sha256;
  final DateTime publishedAt;
  final String title;
  final String description;

  /// Quando presente, clientes com versao corrente menor que esta NAO
  /// devem aplicar esta release (vem de `sparkle:minSupportedAppVersion`
  /// na policy do appcast).
  final Version? minSupportedAppVersion;

  /// 0..100. Quando presente, apenas `hash(machineId) % 100 < value`
  /// clientes participam. Usado para staged rollout (vem de
  /// `sparkle:rolloutPercentage`).
  final int? rolloutPercentage;

  String get targetVersion => version.toString();

  String get installerFileName {
    final uri = Uri.tryParse(downloadUrl);
    final basename = uri == null ? '' : p.basename(uri.path);
    if (basename.toLowerCase().endsWith('.exe')) {
      return basename;
    }
    return 'BackupDatabase-Setup-$targetVersion.exe';
  }
}

@immutable
class AppUpdateDecision {
  const AppUpdateDecision({
    required this.currentVersion,
    required this.latestRelease,
  });

  final Version currentVersion;
  final AppcastRelease? latestRelease;

  bool get isUpdateAvailable => latestRelease != null;
}

@immutable
class AppUpdateSnapshot {
  const AppUpdateSnapshot({
    required this.status,
    this.feedUrl,
    this.currentVersion,
    this.release,
    this.stage,
    this.message,
    this.errorMessage,
    this.lastCheckAt,
    this.lastErrorAt,
    this.lastSource,
    this.lastFailureStage,
    this.lastAttemptNumber,
    this.lastDownloadDuration,
    this.lastCheckDuration,
    this.disabledReason,
    this.blockReason,
  });

  final AppUpdateStatus status;
  final String? feedUrl;
  final String? currentVersion;
  final AppcastRelease? release;
  final AppUpdateStage? stage;
  final String? message;
  final String? errorMessage;
  final DateTime? lastCheckAt;
  final DateTime? lastErrorAt;
  final AppUpdateSource? lastSource;
  final AppUpdateStage? lastFailureStage;
  final int? lastAttemptNumber;
  final Duration? lastDownloadDuration;
  final Duration? lastCheckDuration;

  /// Por que o updater está desabilitado / não rodou. Apenas relevante
  /// quando `status == disabled` (ou quando `initialize()` falhou
  /// catastroficamente e deixou o snapshot em `idle`). UI usa esse campo
  /// para distinguir feed faltando vs. compatibilidade de OS vs. exceção.
  final AppUpdateDisabledReason? disabledReason;

  /// §audit-2026-05-28 wave 4 (UI banner): razão do último bloqueio
  /// (preenchido junto com `status == blockedByActiveBackup`). UI usa
  /// para distinguir backup local vs. remoto vs. file transfer vs.
  /// UAC vs. account do serviço — cada um demanda UX diferente.
  final AppUpdateBlockReason? blockReason;

  static const _unset = Object();

  String? get targetVersion => release?.targetVersion;
  bool get updateAvailable => release != null;

  AppUpdateSnapshot copyWith({
    AppUpdateStatus? status,
    Object? feedUrl = _unset,
    Object? currentVersion = _unset,
    Object? release = _unset,
    Object? stage = _unset,
    Object? message = _unset,
    Object? errorMessage = _unset,
    Object? lastCheckAt = _unset,
    Object? lastErrorAt = _unset,
    Object? lastSource = _unset,
    Object? lastFailureStage = _unset,
    Object? lastAttemptNumber = _unset,
    Object? lastDownloadDuration = _unset,
    Object? lastCheckDuration = _unset,
    Object? disabledReason = _unset,
    Object? blockReason = _unset,
  }) {
    return AppUpdateSnapshot(
      status: status ?? this.status,
      feedUrl: identical(feedUrl, _unset) ? this.feedUrl : feedUrl as String?,
      currentVersion: identical(currentVersion, _unset)
          ? this.currentVersion
          : currentVersion as String?,
      release: identical(release, _unset)
          ? this.release
          : release as AppcastRelease?,
      stage: identical(stage, _unset) ? this.stage : stage as AppUpdateStage?,
      message: identical(message, _unset) ? this.message : message as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      lastCheckAt: identical(lastCheckAt, _unset)
          ? this.lastCheckAt
          : lastCheckAt as DateTime?,
      lastErrorAt: identical(lastErrorAt, _unset)
          ? this.lastErrorAt
          : lastErrorAt as DateTime?,
      lastSource: identical(lastSource, _unset)
          ? this.lastSource
          : lastSource as AppUpdateSource?,
      lastFailureStage: identical(lastFailureStage, _unset)
          ? this.lastFailureStage
          : lastFailureStage as AppUpdateStage?,
      lastAttemptNumber: identical(lastAttemptNumber, _unset)
          ? this.lastAttemptNumber
          : lastAttemptNumber as int?,
      lastDownloadDuration: identical(lastDownloadDuration, _unset)
          ? this.lastDownloadDuration
          : lastDownloadDuration as Duration?,
      lastCheckDuration: identical(lastCheckDuration, _unset)
          ? this.lastCheckDuration
          : lastCheckDuration as Duration?,
      disabledReason: identical(disabledReason, _unset)
          ? this.disabledReason
          : disabledReason as AppUpdateDisabledReason?,
      blockReason: identical(blockReason, _unset)
          ? this.blockReason
          : blockReason as AppUpdateBlockReason?,
    );
  }
}

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef FeedUrlReader = String? Function();
typedef CheckIntervalReader = String? Function();
typedef DirectoryResolver = Future<Directory> Function();
typedef ExitProcess = void Function(int code);

/// Resultado de `Process.start(...detached)`: pid do filho ou `null` se o
/// caller nao conseguir capturar (mantemos compat retro com starters antigos
/// que retornavam `Future<void>`).
@immutable
class DetachedProcessHandle {
  const DetachedProcessHandle({required this.pid});

  final int pid;
}

typedef DetachedProcessStarter =
    Future<DetachedProcessHandle?> Function(
      String executable,
      List<String> arguments,
    );
typedef BeforeInstallHook = Future<void> Function();

/// §audit-2026-05-28 wave 4: o callback agora recebe também o
/// [AppUpdateSource] da checagem. Permite decidir, p.ex., bloquear o
/// install silencioso quando a origem for `periodic`/`startup` (e o
/// SO vai disparar prompt UAC sem usuário olhar) e deixar passar
/// quando for `manual` (usuário sabe que vai aparecer o prompt e está
/// disposto a confirmar).
///
/// §audit-2026-05-28 wave 4 (UI banner): retorna agora
/// [AppUpdateBlockOutcome] (mensagem + razão tipada) em vez de só
/// `String?` — UI usa o `reason` para escolher o tom da banner e
/// renderizar o botão "Atualizar agora" embutido quando aplicável.
typedef InstallReadinessCheck =
    Future<AppUpdateBlockOutcome?> Function(
      AppcastRelease release,
      AppUpdateSource source,
    );
typedef UpdateInstallContextProvider =
    Future<AppUpdateInstallContext> Function(AppcastRelease release);
typedef FreeDiskSpaceProbe = Future<int?> Function(Directory directory);
typedef ProcessAliveCheck = bool Function(int pid);

/// Devolve um identificador estavel da maquina usado APENAS para
/// distribuicao deterministica em staged rollout. Nao precisa ser
/// criptografico nem persistente entre reinstalacoes; basta nao trocar
/// com frequencia (ex.: MachineGuid do Windows).
typedef MachineIdResolver = Future<String?> Function();

enum AppUpdateLaunchOrigin { ui, service }

@immutable
class AppUpdateInstallContext {
  AppUpdateInstallContext({
    required this.origin,
    required this.appMode,
    required this.currentVersion,
    required this.targetVersion,
    required this.relaunchArguments,
    required this.executablePath,
    required this.createdAt,
    int? schemaVersion,
    DateTime? expiresAt,
    String? contextId,
    this.serviceName = 'BackupDatabaseService',
    this.serviceExists,
    this.serviceConfig,
  }) : schemaVersion =
           schemaVersion ?? AutoUpdateService.updateContextSchemaVersion,
       expiresAt =
           expiresAt ?? createdAt.add(AutoUpdateService.updateContextTtl),
       contextId =
           contextId ??
           '${origin.name}-$targetVersion-${createdAt.toUtc().millisecondsSinceEpoch}';

  final AppUpdateLaunchOrigin origin;
  final AppMode appMode;
  final String currentVersion;
  final String targetVersion;
  final List<String> relaunchArguments;
  final String executablePath;
  final DateTime createdAt;
  final int schemaVersion;
  final DateTime expiresAt;
  final String contextId;
  final String serviceName;
  final bool? serviceExists;
  final Map<String, Object?>? serviceConfig;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'contextId': contextId,
      'origin': origin.name,
      'appMode': appMode.name,
      'currentVersion': currentVersion,
      'targetVersion': targetVersion,
      'relaunchArguments': relaunchArguments,
      'executablePath': executablePath,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'serviceName': serviceName,
      'serviceExists': serviceExists,
      'serviceConfig': serviceConfig,
    };
  }
}

class AppUpdateBlockedException implements Exception {
  const AppUpdateBlockedException({
    required this.message,
    required this.status,
    required this.stage,
    this.reason,
  });

  final String message;
  final AppUpdateStatus status;
  final AppUpdateStage stage;

  /// §audit-2026-05-28 wave 4 (UI banner): razão semântica do
  /// bloqueio, vinda do [InstallReadinessCheck]. `null` para legacy
  /// callers que ainda usam só `String message`.
  final AppUpdateBlockReason? reason;

  @override
  String toString() => message;
}

class AppUpdateLockHandle {
  AppUpdateLockHandle(this._file, {Map<String, String>? metadata})
    : _metadata = <String, String>{...?metadata};

  final File _file;
  final Map<String, String> _metadata;

  Future<void> updateMetadata(Map<String, String?> values) async {
    values.forEach((key, value) {
      if (value == null || value.isEmpty) {
        _metadata.remove(key);
      } else {
        _metadata[key] = value;
      }
    });
    await _persist();
  }

  Future<void> _persist() async {
    final buffer = StringBuffer();
    final keys = _metadata.keys.toList()..sort();
    for (final key in keys) {
      buffer.writeln('$key=${_metadata[key]}');
    }
    await _file.writeAsString(buffer.toString(), flush: true);
  }

  Future<void> release() async {
    try {
      if (await _file.exists()) {
        await _file.delete();
      }
    } on Object {
      // Ignorado: o processo pode estar encerrando em paralelo.
    }
  }
}

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
       _processAliveCheck = processAliveCheck ?? _defaultProcessAliveCheck,
       _machineIdResolver = machineIdResolver ?? _defaultMachineIdResolver {
    _applyDefaultNetworkTimeouts(_dio);
  }

  static const int defaultCheckIntervalSeconds = 3600;

  /// Nome da variavel de ambiente (lida via dotenv) para sobrescrever o
  /// intervalo periodico. Valor `0` desativa o timer periodico (so on-demand).
  /// Outros valores positivos sao tratados como segundos (>=60).
  static const String checkIntervalEnvVar =
      'AUTO_UPDATE_CHECK_INTERVAL_SECONDS';

  /// Espaco minimo (bytes) requerido em `staging/updates` antes de iniciar
  /// um download. Usamos 2x o tamanho declarado pelo appcast para acomodar
  /// o instalador alvo + um instalador anterior preservado por
  /// `_cleanupStagedInstallers`. Em `staged/updates` raramente cresce.
  static const int _minFreeSpaceFactor = 2;

  /// Janela curta para confirmar que o instalador silencioso realmente
  /// iniciou (processo vivo + setup.iss removeu o `update_context.json`).
  /// Acima disso, ainda assumimos sucesso para nao bloquear o handoff em
  /// VMs muito lentas, mas registramos a duracao em telemetria.
  static const Duration _installerSpawnGracePeriod = Duration(seconds: 5);

  /// Espera curta antes do `exit()` para o S.O. registrar o spawn detached.
  static const Duration _exitGracePeriod = Duration(milliseconds: 250);

  static const List<String> _installerArguments = <String>[
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
  ];
  static const Duration defaultLockStaleAfter = Duration(hours: 2);
  @visibleForTesting
  static const int updateContextSchemaVersion = 2;
  @visibleForTesting
  static const Duration updateContextTtl = Duration(minutes: 45);

  /// Versao do schema usada nas linhas de `auto_update_history.jsonl`.
  /// Linhas sem `schemaVersion` (legado) sao mantidas; linhas com
  /// `schemaVersion` desconhecida sao descartadas durante a rotacao.
  @visibleForTesting
  static const int diagnosticsSchemaVersion = 1;

  static const Duration _defaultNetworkTimeout = Duration(seconds: 30);
  static const int _maxNetworkAttempts = 3;
  static const Duration _initialRetryDelay = Duration(milliseconds: 500);
  static const Duration _stagedInstallerRetention = Duration(days: 7);
  static const Duration _diagnosticsRetention = Duration(days: 14);
  static const int _maxDiagnosticsFileBytes = 256 * 1024;
  static const String _updateContextFileName = 'update_context.json';
  static const String _updateDiagnosticsFileName = 'auto_update_history.jsonl';
  static const String _lockFileName = 'auto_update.lock';
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
      _updateContextFileName,
    );
  }

  static String diagnosticsSupportPath({Map<String, String>? environment}) {
    return p.join(
      machineRootSupportPath(environment: environment),
      MachineStorageLayout.staging,
      MachineStorageLayout.updates,
      _updateDiagnosticsFileName,
    );
  }

  static String lockFileSupportPath({Map<String, String>? environment}) {
    return p.join(
      machineRootSupportPath(environment: environment),
      MachineStorageLayout.locks,
      _lockFileName,
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

  /// Resolve o label `origin` para o `auto_update_history.jsonl` (P1#8).
  /// Usa o `ServiceModeDetector` cached em vez de detectar a cada call —
  /// o boot já chamou `isServiceMode` no startup, então é apenas um
  /// getter de cache aqui.
  static String _resolveOriginLabel() {
    return ServiceModeDetector.isServiceMode() ? 'service' : 'ui';
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
    var lockReleased = false;
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
          status: AppUpdateStatus.installing,
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
        await beforeInstallHook!.call();
      }

      installContext = await _persistInstallContext(
        release: release,
        currentVersion: currentVersion.toString(),
      );

      await transitionStage(AppUpdateStage.launchingInstaller);

      final spawnHandle = await _launchInstaller(installer);
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
      await lockHandle.release();
      lockReleased = true;
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
      await _removeInstallContextOnEarlyFailure(e.stage);
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
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.error,
          currentVersion: currentVersion.toString(),
          stage: currentStage,
          message: 'Falha ao processar a atualizacao automatica.',
          errorMessage: e.toString(),
          lastCheckAt: now,
          lastErrorAt: now,
          lastSource: source,
          lastFailureStage: currentStage,
          lastAttemptNumber: attemptNumber,
          lastDownloadDuration: downloadDuration,
          lastCheckDuration: checkStopwatch.elapsed,
        ),
      );
      await _removeInstallContextOnEarlyFailure(currentStage);
      await _persistDiagnostics(
        source: source,
        attemptNumber: attemptNumber,
        currentVersion: currentVersion.toString(),
        targetVersion: targetVersion,
        stage: currentStage,
        status: AppUpdateStatus.error,
        startedAt: now,
        duration: checkStopwatch.elapsed,
        errorMessage: e.toString(),
        installerBytes: installerBytes,
        downloadDuration: downloadDuration,
      );
    } finally {
      if (!lockReleased) {
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

  Future<File> _downloadInstaller(AppcastRelease release) async {
    final updatesDir = await _updatesDirectoryResolver();
    await updatesDir.create(recursive: true);
    await _cleanupStagedInstallers(
      preserveInstallerName: release.installerFileName,
    );

    await _ensureSufficientDiskSpace(
      updatesDir: updatesDir,
      release: release,
    );

    final targetFile = File(p.join(updatesDir.path, release.installerFileName));
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    await _runWithRetry<void>(
      label: 'download do instalador',
      action: () {
        return _dio.download(
          release.downloadUrl,
          targetFile.path,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
          ),
        );
      },
    );

    return targetFile;
  }

  Future<void> _ensureSufficientDiskSpace({
    required Directory updatesDir,
    required AppcastRelease release,
  }) async {
    final freeBytes = await _freeDiskSpaceProbe(updatesDir);
    if (freeBytes == null) {
      // Probe nao suportado nesta plataforma/instalacao; nao bloqueia.
      return;
    }
    final required = release.fileSizeBytes * _minFreeSpaceFactor;
    if (freeBytes < required) {
      throw StateError(
        'Espaco insuficiente em ${updatesDir.path} para baixar '
        '${release.installerFileName}. '
        'Livre: $freeBytes B, necessario aproximado: $required B '
        '(${_minFreeSpaceFactor}x o tamanho do instalador).',
      );
    }
  }

  Future<DetachedProcessHandle?> _launchInstaller(File installer) async {
    LoggerService.info(
      'Iniciando instalador silencioso: ${installer.path} '
      '${_installerArguments.join(' ')}',
    );
    return _detachedProcessStarter(installer.path, _installerArguments);
  }

  /// Confirma que o instalador detached realmente iniciou. Estrategia:
  /// 1. Pula a checagem se o starter custom nao expoe pid (testes).
  /// 2. Espera ate `_installerSpawnGracePeriod` (5s) verificando o pid em
  ///    janelas curtas. Se o processo morrer cedo, devolve false.
  /// 3. Como heuristica adicional, considera vivo se o `update_context.json`
  ///    ainda existir (o `setup.iss` so apaga apos `restore_update_state.ps1`).
  ///
  /// Retorna `true` quando assumimos sucesso (suficiente para chamar `exit`).
  Future<bool> _waitForInstallerSpawn(DetachedProcessHandle? handle) async {
    if (handle == null) {
      // Fallback retro: starter custom (ex.: testes) que nao expoe pid;
      // assume sucesso para preservar o comportamento anterior.
      return true;
    }

    final deadline = DateTime.now().add(_installerSpawnGracePeriod);
    const pollInterval = Duration(milliseconds: 250);
    var attempts = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempts++;
      if (_processAliveCheck(handle.pid)) {
        // Encontramos o pid pelo menos uma vez — o Inno extrai recursos no
        // %TEMP% por ~1s antes de spawnar children; basta o pai estar vivo.
        if (attempts >= 2) {
          return true;
        }
      } else if (attempts >= 2) {
        // Duas tentativas seguidas sem o pid: confirmamos que morreu cedo.
        return false;
      }
      await Future<void>.delayed(pollInterval);
    }
    // Esgotou janela com checks inconclusivos: assume sucesso para nao
    // bloquear o handoff em VMs muito lentas.
    return true;
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
  }) async {
    await locksDir.create(recursive: true);

    final lockFile = File(p.join(locksDir.path, _lockFileName));
    final acquiredAt = (now ?? DateTime.now()).toUtc();
    final aliveCheck = processAliveCheck ?? _defaultProcessAliveCheck;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await lockFile.create(exclusive: true);
        final handle = AppUpdateLockHandle(lockFile);
        await handle.updateMetadata({
          'pid': '$pid',
          'acquiredAt': acquiredAt.toIso8601String(),
          ...metadata,
        });
        return handle;
      } on PathExistsException {
        final ownerPid = await _readLockOwnerPid(lockFile);
        final ownerAlive = ownerPid == null || aliveCheck(ownerPid);
        final isStaleByAge = await _isStaleLockFile(
          lockFile,
          staleAfter: staleAfter,
          now: acquiredAt,
        );

        // Considera obsoleto se (a) excedeu janela de stale OU (b) o
        // processo dono nao existe mais no S.O. Combinacao reduz a janela
        // de bloqueio apos crash do dono (antes esperavamos 2h cheias).
        final isStale = isStaleByAge || !ownerAlive;
        if (!isStale) {
          final summary = await _describeLockOwner(lockFile);
          LoggerService.info(
            'AutoUpdateService: lock global ainda valido em '
            '${lockFile.path}${summary == null ? '' : ' ($summary)'}',
          );
          return null;
        }
        if (!ownerAlive) {
          LoggerService.warning(
            'AutoUpdateService: lock global pertence ao pid=$ownerPid '
            'que nao existe mais; tratando como stale.',
          );
        }

        try {
          await lockFile.delete();
        } on Object catch (e, s) {
          LoggerService.info(
            'AutoUpdateService: lock obsoleto nao pode ser removido',
            e,
            s,
          );
          return null;
        }
      } on FileSystemException catch (e, s) {
        LoggerService.info(
          'AutoUpdateService: falha ao adquirir lock global',
          e,
          s,
        );
        return null;
      }
    }

    return null;
  }

  Future<AppUpdateLockHandle?> _tryAcquireLock({
    required AppUpdateSource source,
    required String currentVersion,
    required int attemptNumber,
  }) async {
    final locksDir = await _locksDirectoryResolver();
    final handle = await tryAcquireGlobalLock(
      locksDir: locksDir,
      metadata: {
        'source': source.name,
        'currentVersion': currentVersion,
        'attempt': '$attemptNumber',
        'stage': _stageToken(AppUpdateStage.fetchingFeed),
      },
      processAliveCheck: _processAliveCheck,
    );
    if (handle == null) {
      LoggerService.info(
        'AutoUpdateService: lock global ocupado por outro processo',
      );
    }
    return handle;
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

  /// Heuristica leve para checar se um PID Windows segue ativo. Usa
  /// `tasklist /FI` com filtro por PID. Em qualquer falha, retorna `true`
  /// (assume vivo) para nao remover um lock potencialmente valido por engano.
  static bool _defaultProcessAliveCheck(int pid) {
    if (!Platform.isWindows || pid <= 0) {
      return true;
    }
    try {
      final result = Process.runSync('tasklist.exe', <String>[
        '/FI',
        'PID eq $pid',
        '/NH',
      ]);
      if (result.exitCode != 0) {
        return true;
      }
      final output = result.stdout.toString();
      // `tasklist` imprime "INFO: No tasks are running..." quando nao encontra.
      return !output.contains('No tasks are running') &&
          !output.contains('Nenhuma tarefa em execu');
    } on Object {
      return true;
    }
  }

  Future<AppUpdateInstallContext> _persistInstallContext({
    required AppcastRelease release,
    required String currentVersion,
  }) async {
    final updatesDir = await _updatesDirectoryResolver();
    await updatesDir.create(recursive: true);
    await _cleanupUpdateContextIfExpired(
      File(p.join(updatesDir.path, _updateContextFileName)),
    );
    final context =
        await installContextProvider?.call(release) ??
        AppUpdateInstallContext(
          origin: AppUpdateLaunchOrigin.ui,
          appMode: currentAppMode,
          currentVersion: currentVersion,
          targetVersion: release.targetVersion,
          relaunchArguments: List<String>.of(Platform.executableArguments),
          executablePath: Platform.resolvedExecutable,
          createdAt: DateTime.now(),
        );

    final file = File(p.join(updatesDir.path, _updateContextFileName));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert(context.toJson())}\n',
      flush: true,
    );
    return context;
  }

  /// Remove `update_context.json` quando o pipeline aborta antes de
  /// `launchingInstaller`. Sem isso, restos de contextos de falhas
  /// intermediarias poderiam ser interpretados por uma execucao manual
  /// do `restore_update_state.ps1` (fora do fluxo normal) — operadores
  /// confundem o estado.
  Future<void> _removeInstallContextOnEarlyFailure(
    AppUpdateStage failureStage,
  ) async {
    if (failureStage == AppUpdateStage.launchingInstaller ||
        failureStage == AppUpdateStage.completed) {
      // Apos lancar o instalador, ele e' quem decide o que fazer com o
      // contexto — preservamos.
      return;
    }
    try {
      final updatesDir = await _updatesDirectoryResolver();
      final file = File(p.join(updatesDir.path, _updateContextFileName));
      if (await file.exists()) {
        await file.delete();
        LoggerService.info(
          'AutoUpdateService: update_context.json removido apos falha em '
          '${_stageToken(failureStage)}.',
        );
      }
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao remover update_context.json apos erro pre-launch',
        e,
        s,
      );
    }
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
  }) async {
    try {
      final updatesDir = await _updatesDirectoryResolver();
      await updatesDir.create(recursive: true);
      final file = File(p.join(updatesDir.path, _updateDiagnosticsFileName));
      await _rotateDiagnosticsIfNeeded(file);

      double? downloadMbps;
      if (installerBytes != null &&
          installerBytes > 0 &&
          downloadDuration != null &&
          downloadDuration.inMilliseconds > 0) {
        final seconds = downloadDuration.inMilliseconds / 1000.0;
        downloadMbps = (installerBytes / (1024 * 1024)) / seconds;
      }

      final record = <String, Object?>{
        'schemaVersion': diagnosticsSchemaVersion,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'attemptNumber': attemptNumber,
        'source': source.name,
        // §audit-2026-05-28: maquinas com UI + service ativos
        // simultaneamente nao distinguiam qual processo gerou cada
        // entry. `origin` (resolvido via installContextProvider) +
        // `processPid` permitem correlacionar com logs do processo.
        'origin': _resolveOriginLabel(),
        'processPid': pid,
        'status': status.name,
        'stage': _stageToken(stage),
        'currentVersion': currentVersion,
        'targetVersion': targetVersion,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'installerBytes': ?installerBytes,
        'downloadDurationMs': ?downloadDuration?.inMilliseconds,
        'downloadMbps': downloadMbps != null
            ? double.parse(downloadMbps.toStringAsFixed(3))
            : null,
        'error': errorMessage,
      };
      await file.writeAsString(
        '${jsonEncode(record)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao persistir diagnostico de auto update',
        e,
        s,
      );
    }
  }

  Future<void> _cleanupStaleUpdateArtifacts() async {
    final updatesDir = await _updatesDirectoryResolver();
    if (!await updatesDir.exists()) {
      return;
    }

    final contextFile = File(p.join(updatesDir.path, _updateContextFileName));
    await _cleanupUpdateContextIfExpired(contextFile);

    final diagnosticsFile = File(
      p.join(updatesDir.path, _updateDiagnosticsFileName),
    );
    await _rotateDiagnosticsIfNeeded(diagnosticsFile);
  }

  Future<void> _cleanupUpdateContextIfExpired(File file) async {
    if (!await file.exists()) {
      return;
    }

    if (!await _isUpdateContextExpired(file)) {
      return;
    }

    try {
      await file.delete();
      LoggerService.info(
        'AutoUpdateService: update_context.json expirado removido de '
        '${file.path}',
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao remover update_context.json expirado',
        e,
        s,
      );
    }
  }

  @visibleForTesting
  static Future<bool> isUpdateContextExpired(
    File file, {
    DateTime? now,
  }) {
    return _isUpdateContextExpired(file, now: now);
  }

  static Future<bool> _isUpdateContextExpired(
    File file, {
    DateTime? now,
  }) async {
    final reference = (now ?? DateTime.now()).toUtc();
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return true;
      }
      final expiresAt =
          _tryParseIsoDateTime(decoded['expiresAt']) ??
          _tryParseIsoDateTime(decoded['createdAt'])?.add(updateContextTtl);
      if (expiresAt == null) {
        final modified = (await file.stat()).modified.toUtc();
        return reference.isAfter(modified.add(updateContextTtl));
      }
      return reference.isAfter(expiresAt.toUtc());
    } on Object {
      return true;
    }
  }

  Future<void> _rotateDiagnosticsIfNeeded(File file) async {
    if (!await file.exists()) {
      return;
    }

    final stat = await file.stat();
    final now = DateTime.now().toUtc();
    if (stat.size <= _maxDiagnosticsFileBytes &&
        now.difference(stat.modified.toUtc()) <= _diagnosticsRetention) {
      return;
    }

    try {
      final rotated = await compactDiagnosticsLines(
        await file.readAsLines(),
        now: now,
      );
      if (rotated.isEmpty) {
        await file.delete();
        return;
      }
      await file.writeAsString('${rotated.join('\n')}\n', flush: true);
    } on Object catch (e, s) {
      LoggerService.warning(
        'Falha ao rotacionar historico de auto update',
        e,
        s,
      );
    }
  }

  @visibleForTesting
  static Future<List<String>> compactDiagnosticsLines(
    List<String> lines, {
    required DateTime now,
    Duration retention = _diagnosticsRetention,
    int maxBytes = _maxDiagnosticsFileBytes,
  }) async {
    final cutoff = now.toUtc().subtract(retention);
    final kept = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        // Linhas legadas (sem schemaVersion) sao aceitas como
        // schemaVersion=null/0; linhas com schemaVersion futura
        // (desconhecida) sao descartadas para evitar misinterpretacao.
        final rawSchema = decoded['schemaVersion'];
        if (rawSchema != null) {
          final schema = rawSchema is int
              ? rawSchema
              : int.tryParse(rawSchema.toString());
          if (schema == null || schema > diagnosticsSchemaVersion) {
            continue;
          }
        }

        final timestamp = _tryParseIsoDateTime(decoded['timestamp']);
        if (timestamp == null || timestamp.isBefore(cutoff)) {
          continue;
        }
        kept.add(trimmed);
      } on Object {
        continue;
      }
    }

    var estimatedBytes = kept.fold<int>(
      0,
      (total, line) => total + utf8.encode(line).length + 1,
    );
    while (kept.isNotEmpty && estimatedBytes > maxBytes) {
      final removed = kept.removeAt(0);
      estimatedBytes -= utf8.encode(removed).length + 1;
    }
    return kept;
  }

  Future<void> _cleanupStagedInstallers({String? preserveInstallerName}) async {
    final updatesDir = await _updatesDirectoryResolver();
    if (!await updatesDir.exists()) {
      return;
    }

    final now = DateTime.now();
    final installers = <File>[];
    await for (final entity in updatesDir.list()) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.exe') {
        installers.add(entity);
      }
    }

    installers.sort((a, b) {
      final aModified = a.statSync().modified;
      final bModified = b.statSync().modified;
      return bModified.compareTo(aModified);
    });

    var keptRecentCount = 0;
    final maxRecentKeep = preserveInstallerName == null ? 2 : 1;
    for (final installer in installers) {
      final name = p.basename(installer.path);
      final modified = (await installer.stat()).modified;
      final isPreservedTarget =
          preserveInstallerName != null && name == preserveInstallerName;
      final canKeepAsPrevious =
          !isPreservedTarget &&
          keptRecentCount < maxRecentKeep &&
          now.difference(modified) <= _stagedInstallerRetention;

      if (isPreservedTarget) {
        continue;
      }
      if (canKeepAsPrevious) {
        keptRecentCount++;
        continue;
      }
      try {
        await installer.delete();
      } on Object catch (e, s) {
        LoggerService.warning(
          'Falha ao remover instalador antigo de staging: ${installer.path}',
          e,
          s,
        );
      }
    }
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

  static void _applyDefaultNetworkTimeouts(Dio dio) {
    dio.options = dio.options.copyWith(
      connectTimeout: dio.options.connectTimeout ?? _defaultNetworkTimeout,
      receiveTimeout: dio.options.receiveTimeout ?? _defaultNetworkTimeout,
      sendTimeout: dio.options.sendTimeout ?? _defaultNetworkTimeout,
    );
  }

  static Version? _tryParseVersion(String? raw) =>
      AppcastParser.tryParseVersion(raw);

  static DateTime? _tryParseIsoDateTime(Object? raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

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

  static String _stageToken(AppUpdateStage stage) {
    return switch (stage) {
      AppUpdateStage.blockedByOtherInstance => 'blocked_by_other_instance',
      AppUpdateStage.blockedByActiveBackup => 'blocked_by_active_backup',
      AppUpdateStage.fetchingFeed => 'fetching_feed',
      AppUpdateStage.evaluatingRelease => 'evaluating_release',
      AppUpdateStage.downloadingInstaller => 'downloading_installer',
      AppUpdateStage.validatingInstaller => 'validating_installer',
      AppUpdateStage.preparingInstall => 'preparing_install',
      AppUpdateStage.launchingInstaller => 'launching_installer',
      AppUpdateStage.completed => 'completed',
    };
  }

  static Future<int?> _readLockOwnerPid(File file) async {
    try {
      final lines = await file.readAsLines();
      for (final line in lines) {
        final separator = line.indexOf('=');
        if (separator <= 0) {
          continue;
        }
        final key = line.substring(0, separator).trim();
        if (key != 'pid') {
          continue;
        }
        final value = line.substring(separator + 1).trim();
        return int.tryParse(value);
      }
    } on Object {
      // Ignorado: arquivo pode estar parcialmente escrito.
    }
    return null;
  }

  static Future<String?> _describeLockOwner(File file) async {
    try {
      final lines = await file.readAsLines();
      if (lines.isEmpty) {
        return null;
      }

      final parts = <String>[];
      for (final line in lines) {
        final separatorIndex = line.indexOf('=');
        if (separatorIndex <= 0) {
          continue;
        }
        final key = line.substring(0, separatorIndex).trim();
        final value = line.substring(separatorIndex + 1).trim();
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        if (key == 'source' ||
            key == 'attempt' ||
            key == 'stage' ||
            key == 'targetVersion') {
          parts.add('$key=$value');
        }
      }
      if (parts.isEmpty) {
        return null;
      }
      return parts.join(', ');
    } on Object {
      return null;
    }
  }

  static Future<bool> _isStaleLockFile(
    File file, {
    required Duration staleAfter,
    required DateTime now,
  }) async {
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return false;
      }
      return now.difference(stat.modified.toUtc()) > staleAfter;
    } on Object {
      return false;
    }
  }
}
