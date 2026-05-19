import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:xml/xml.dart';

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
  });

  final Version version;
  final String downloadUrl;
  final int fileSizeBytes;
  final String sha256;
  final DateTime publishedAt;
  final String title;
  final String description;

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
    );
  }
}

typedef PackageInfoLoader = Future<PackageInfo> Function();
typedef FeedUrlReader = String? Function();
typedef DirectoryResolver = Future<Directory> Function();
typedef ExitProcess = void Function(int code);
typedef DetachedProcessStarter =
    Future<void> Function(String executable, List<String> arguments);
typedef BeforeInstallHook = Future<void> Function();
typedef InstallReadinessCheck =
    Future<String?> Function(AppcastRelease release);
typedef UpdateInstallContextProvider =
    Future<AppUpdateInstallContext> Function(AppcastRelease release);

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
  });

  final String message;
  final AppUpdateStatus status;
  final AppUpdateStage stage;

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
    DirectoryResolver? locksDirectoryResolver,
    DirectoryResolver? updatesDirectoryResolver,
    DetachedProcessStarter? detachedProcessStarter,
    ExitProcess? exitProcess,
  }) : _dio = dio ?? Dio(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _feedUrlReader =
           feedUrlReader ?? (() => dotenv.env['AUTO_UPDATE_FEED_URL']),
       _locksDirectoryResolver =
           locksDirectoryResolver ?? resolveMachineLocksDirectory,
       _updatesDirectoryResolver =
           updatesDirectoryResolver ?? resolveMachineUpdateDownloadsDirectory,
       _detachedProcessStarter =
           detachedProcessStarter ?? _defaultDetachedProcessStarter,
       _exitProcess = exitProcess ?? exit {
    _applyDefaultNetworkTimeouts(_dio);
  }

  static const int defaultCheckIntervalSeconds = 3600;
  static const String _sparkleNamespace =
      'http://www.andymatuschak.org/xml-namespaces/sparkle';
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
  final DirectoryResolver _locksDirectoryResolver;
  final DirectoryResolver _updatesDirectoryResolver;
  final DetachedProcessStarter _detachedProcessStarter;
  final ExitProcess _exitProcess;

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

  Future<void> initialize() async {
    if (_isInitialized) {
      LoggerService.warning('AutoUpdateService ja foi inicializado');
      return;
    }

    final currentVersion = await _resolveCurrentVersion();
    final configuredFeedUrl = _feedUrlReader()?.trim();

    _isInitialized = true;
    _feedUrl = configuredFeedUrl != null && configuredFeedUrl.isNotEmpty
        ? configuredFeedUrl
        : null;

    if (!Platform.isWindows) {
      _emitSnapshot(
        AppUpdateSnapshot(
          status: AppUpdateStatus.disabled,
          currentVersion: currentVersion.toString(),
          stage: AppUpdateStage.completed,
          message: 'Atualizacoes automaticas disponiveis apenas no Windows.',
        ),
      );
      LoggerService.info('AutoUpdateService desabilitado fora do Windows');
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
        ),
      );
      LoggerService.warning(
        'AUTO_UPDATE_FEED_URL nao configurada. Atualizacoes automáticas '
        'desabilitadas.',
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

    LoggerService.info('AutoUpdateService pronto com feed $_feedUrl');
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

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      unawaited(checkNow(source: AppUpdateSource.periodic));
    });

    LoggerService.info(
      'AutoUpdateService: verificacoes periodicas configuradas em '
      '${interval.inSeconds}s',
    );
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

  @visibleForTesting
  static List<AppcastRelease> parseAppcast(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    final items = document.findAllElements('item');
    final byVersion = <String, AppcastRelease>{};

    for (final item in items) {
      final enclosure = item.getElement('enclosure');
      if (enclosure == null) {
        continue;
      }

      final os =
          enclosure.getAttribute('os', namespace: _sparkleNamespace) ??
          enclosure.getAttribute('sparkle:os');
      if ((os ?? '').toLowerCase() != 'windows') {
        continue;
      }

      final versionRaw =
          enclosure.getAttribute('version', namespace: _sparkleNamespace) ??
          enclosure.getAttribute('sparkle:version');
      final url = enclosure.getAttribute('url');
      final lengthRaw = enclosure.getAttribute('length');
      final sha256 =
          enclosure.getAttribute('sha256') ??
          enclosure.getAttribute('sha256', namespace: _sparkleNamespace) ??
          enclosure.getAttribute('sparkle:sha256');

      if (versionRaw == null ||
          url == null ||
          lengthRaw == null ||
          sha256 == null ||
          sha256.trim().isEmpty) {
        continue;
      }

      final version = _tryParseVersion(versionRaw);
      final length = int.tryParse(lengthRaw);
      if (version == null || length == null || length <= 0) {
        continue;
      }

      final title =
          item.getElement('title')?.innerText.trim() ?? 'Version $version';
      final description =
          item.getElement('description')?.innerText.trim() ?? '';
      final publishedAt =
          _tryParsePubDate(item.getElement('pubDate')?.innerText) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      final release = AppcastRelease(
        version: version,
        downloadUrl: url,
        fileSizeBytes: length,
        sha256: sha256.toLowerCase(),
        publishedAt: publishedAt,
        title: title,
        description: description,
      );

      final key = version.toString();
      final existing = byVersion[key];
      if (existing == null ||
          release.publishedAt.isAfter(existing.publishedAt)) {
        byVersion[key] = release;
      }
    }

    final releases = byVersion.values.toList()
      ..sort((a, b) {
        final versionComparison = b.version.compareTo(a.version);
        if (versionComparison != 0) {
          return versionComparison;
        }
        return b.publishedAt.compareTo(a.publishedAt);
      });
    return releases;
  }

  @visibleForTesting
  static AppUpdateDecision evaluateRelease({
    required List<AppcastRelease> releases,
    required Version currentVersion,
  }) {
    for (final release in releases) {
      if (release.version > currentVersion) {
        return AppUpdateDecision(
          currentVersion: currentVersion,
          latestRelease: release,
        );
      }
    }

    return AppUpdateDecision(
      currentVersion: currentVersion,
      latestRelease: null,
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

    final lockHandle = await _tryAcquireLock(
      source: source,
      currentVersion: currentVersion.toString(),
      attemptNumber: attemptNumber,
    );
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
      currentStage = AppUpdateStage.evaluatingRelease;
      await lockHandle.updateMetadata({
        'stage': _stageToken(currentStage),
      });
      final decision = evaluateRelease(
        releases: releases,
        currentVersion: currentVersion,
      );

      if (!decision.isUpdateAvailable) {
        checkStopwatch.stop();
        await lockHandle.updateMetadata({
          'stage': _stageToken(AppUpdateStage.completed),
        });
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
      await lockHandle.updateMetadata({
        'stage': _stageToken(AppUpdateStage.evaluatingRelease),
        'targetVersion': release.targetVersion,
      });

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

      currentStage = AppUpdateStage.downloadingInstaller;
      await lockHandle.updateMetadata({
        'stage': _stageToken(currentStage),
      });
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
      _logTelemetry(
        'download do instalador concluido',
        source: source,
        attemptNumber: attemptNumber,
        stage: currentStage,
        targetVersion: release.targetVersion,
        totalDuration: downloadDuration,
      );

      currentStage = AppUpdateStage.validatingInstaller;
      await lockHandle.updateMetadata({
        'stage': _stageToken(currentStage),
      });
      await validateDownloadedInstaller(installer, release);

      currentStage = AppUpdateStage.preparingInstall;
      await lockHandle.updateMetadata({
        'stage': _stageToken(currentStage),
      });
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

      final blockReason = await installReadinessCheck?.call(release);
      if (blockReason != null) {
        throw AppUpdateBlockedException(
          message: blockReason,
          status: AppUpdateStatus.blockedByActiveBackup,
          stage: AppUpdateStage.blockedByActiveBackup,
        );
      }

      if (beforeInstallHook != null) {
        await beforeInstallHook!.call();
      }

      await _persistInstallContext(
        release: release,
        currentVersion: currentVersion.toString(),
      );

      currentStage = AppUpdateStage.launchingInstaller;
      await lockHandle.updateMetadata({
        'stage': _stageToken(currentStage),
      });
      await _launchInstaller(installer);

      checkStopwatch.stop();
      await lockHandle.updateMetadata({
        'stage': _stageToken(AppUpdateStage.completed),
      });
      _logTelemetry(
        'instalador silencioso iniciado',
        source: source,
        attemptNumber: attemptNumber,
        stage: currentStage,
        targetVersion: release.targetVersion,
        totalDuration: checkStopwatch.elapsed,
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
      );
      await lockHandle.release();
      lockReleased = true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _exitProcess(0);
    } on AppUpdateBlockedException catch (e) {
      if (checkStopwatch.isRunning) {
        checkStopwatch.stop();
      }
      LoggerService.warning(
        'Auto update bloqueado antes da instalacao: ${e.message}',
      );
      await lockHandle.updateMetadata({
        'stage': _stageToken(e.stage),
      });
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
        ),
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

  Future<void> _launchInstaller(File installer) async {
    LoggerService.info(
      'Iniciando instalador silencioso: ${installer.path} '
      '${_installerArguments.join(' ')}',
    );
    await _detachedProcessStarter(installer.path, _installerArguments);
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
  }) async {
    await locksDir.create(recursive: true);

    final lockFile = File(p.join(locksDir.path, _lockFileName));
    final acquiredAt = (now ?? DateTime.now()).toUtc();

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
        final isStale = await _isStaleLockFile(
          lockFile,
          staleAfter: staleAfter,
          now: acquiredAt,
        );
        if (!isStale) {
          final summary = await _describeLockOwner(lockFile);
          LoggerService.info(
            'AutoUpdateService: lock global ainda valido em '
            '${lockFile.path}${summary == null ? '' : ' ($summary)'}',
          );
          return null;
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

  static Future<void> _defaultDetachedProcessStarter(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    );
  }

  Future<void> _persistInstallContext({
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
  }) async {
    try {
      final updatesDir = await _updatesDirectoryResolver();
      await updatesDir.create(recursive: true);
      final file = File(p.join(updatesDir.path, _updateDiagnosticsFileName));
      await _rotateDiagnosticsIfNeeded(file);
      final record = <String, Object?>{
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'attemptNumber': attemptNumber,
        'source': source.name,
        'status': status.name,
        'stage': _stageToken(stage),
        'currentVersion': currentVersion,
        'targetVersion': targetVersion,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'durationMs': duration.inMilliseconds,
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

  static Version? _tryParseVersion(String? raw) {
    final normalized = raw?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    final withoutPrefix = normalized.startsWith('v')
        ? normalized.substring(1)
        : normalized;
    try {
      return Version.parse(withoutPrefix);
    } on FormatException {
      return null;
    }
  }

  static DateTime? _tryParsePubDate(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    try {
      return HttpDate.parse(value).toUtc();
    } on Object {
      try {
        return DateFormat(
          'EEE, dd MMM yyyy HH:mm:ss Z',
          'en_US',
        ).parseUtc(value);
      } on Object {
        return null;
      }
    }
  }

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
  }) {
    final details = <String>[
      'tentativa=$attemptNumber',
      'origem=${source.name}',
      'etapa=${_stageToken(stage)}',
      if (currentVersion != null) 'versaoAtual=$currentVersion',
      if (targetVersion != null) 'versaoAlvo=$targetVersion',
      if (totalDuration != null) 'duracaoMs=${totalDuration.inMilliseconds}',
    ];
    LoggerService.info('AutoUpdateService: $message (${details.join(', ')})');
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
