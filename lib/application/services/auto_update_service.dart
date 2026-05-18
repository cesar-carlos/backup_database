import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/file_hash_utils.dart';
import 'package:backup_database/core/utils/logger_service.dart';
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
  upToDate,
  error,
  disabled,
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
    this.message,
    this.errorMessage,
    this.lastCheckAt,
    this.lastErrorAt,
    this.lastSource,
  });

  final AppUpdateStatus status;
  final String? feedUrl;
  final String? currentVersion;
  final AppcastRelease? release;
  final String? message;
  final String? errorMessage;
  final DateTime? lastCheckAt;
  final DateTime? lastErrorAt;
  final AppUpdateSource? lastSource;

  static const _unset = Object();

  String? get targetVersion => release?.targetVersion;
  bool get updateAvailable => release != null;

  AppUpdateSnapshot copyWith({
    AppUpdateStatus? status,
    Object? feedUrl = _unset,
    Object? currentVersion = _unset,
    Object? release = _unset,
    Object? message = _unset,
    Object? errorMessage = _unset,
    Object? lastCheckAt = _unset,
    Object? lastErrorAt = _unset,
    Object? lastSource = _unset,
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
       _exitProcess = exitProcess ?? exit;

  static const int defaultCheckIntervalSeconds = 3600;
  static const String _sparkleNamespace =
      'http://www.andymatuschak.org/xml-namespaces/sparkle';
  static const List<String> _installerArguments = <String>[
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
  ];
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
  bool _isInitialized = false;
  String? _feedUrl;
  BeforeInstallHook? _beforeInstallHook;
  AppUpdateSnapshot _snapshot = const AppUpdateSnapshot(
    status: AppUpdateStatus.idle,
  );

  Stream<AppUpdateSnapshot> get snapshots => _snapshotController.stream;
  AppUpdateSnapshot get snapshot => _snapshot;
  bool get isInitialized =>
      _isInitialized && _snapshot.status != AppUpdateStatus.disabled;
  String? get feedUrl => _feedUrl;

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
        message: 'Atualizador pronto para verificar novas versoes.',
      ),
    );

    LoggerService.info('AutoUpdateService pronto com feed $_feedUrl');
  }

  void setBeforeInstallHook(BeforeInstallHook? hook) {
    _beforeInstallHook = hook;
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

    _activeCheck = _runCheck(source).whenComplete(() {
      _activeCheck = null;
    });
    return _activeCheck;
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

    final lockHandle = await _tryAcquireLock();
    if (lockHandle == null) {
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.idle,
          message:
              'Outra instancia da aplicacao ja esta processando a atualizacao.',
          errorMessage: null,
          lastSource: source,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final currentVersion = await _resolveCurrentVersion();

    try {
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.checking,
          currentVersion: currentVersion.toString(),
          feedUrl: _feedUrl,
          release: null,
          message: 'Verificando novas versoes no feed configurado...',
          errorMessage: null,
          lastSource: source,
        ),
      );

      final releases = await _fetchReleases();
      final decision = evaluateRelease(
        releases: releases,
        currentVersion: currentVersion,
      );

      if (!decision.isUpdateAvailable) {
        _emitSnapshot(
          _snapshot.copyWith(
            status: AppUpdateStatus.upToDate,
            currentVersion: currentVersion.toString(),
            release: null,
            message: 'Aplicacao ja esta na versao mais recente.',
            errorMessage: null,
            lastCheckAt: now,
            lastSource: source,
          ),
        );
        return;
      }

      final release = decision.latestRelease!;

      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.updateAvailable,
          currentVersion: currentVersion.toString(),
          release: release,
          message:
              'Nova versao ${release.targetVersion} encontrada. '
              'Iniciando download silencioso.',
          errorMessage: null,
          lastCheckAt: now,
          lastSource: source,
        ),
      );

      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.downloading,
          release: release,
          message:
              'Baixando instalador ${release.installerFileName} para staging...',
        ),
      );

      final installer = await _downloadInstaller(release);
      await validateDownloadedInstaller(installer, release);

      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.installing,
          release: release,
          message:
              'Instalador validado. Preparando troca silenciosa para '
              '${release.targetVersion}.',
        ),
      );

      if (_beforeInstallHook != null) {
        await _beforeInstallHook!.call();
      }

      await _launchInstaller(installer);

      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.installing,
          release: release,
          message:
              'Instalador iniciado em background. Encerrando processo atual...',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 250));
      _exitProcess(0);
    } on Object catch (e, s) {
      LoggerService.error('Erro no pipeline de auto update', e, s);
      _emitSnapshot(
        _snapshot.copyWith(
          status: AppUpdateStatus.error,
          currentVersion: currentVersion.toString(),
          message: 'Falha ao processar a atualizacao automatica.',
          errorMessage: e.toString(),
          lastCheckAt: now,
          lastErrorAt: now,
          lastSource: source,
        ),
      );
    } finally {
      await lockHandle.release();
    }
  }

  Future<List<AppcastRelease>> _fetchReleases() async {
    final response = await _dio.get<String>(
      _feedUrl!,
      options: Options(responseType: ResponseType.plain),
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

    final targetFile = File(p.join(updatesDir.path, release.installerFileName));
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    await _dio.download(
      release.downloadUrl,
      targetFile.path,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
      ),
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

  Future<_UpdateLockHandle?> _tryAcquireLock() async {
    final locksDir = await _locksDirectoryResolver();
    await locksDir.create(recursive: true);

    final file = File(p.join(locksDir.path, 'auto_update.lock'));
    final raf = await file.open(mode: FileMode.write);

    try {
      await raf.lock(FileLock.exclusive);
      return _UpdateLockHandle(raf);
    } on FileSystemException catch (e, s) {
      LoggerService.info(
        'AutoUpdateService: lock global ocupado por outro processo',
        e,
        s,
      );
      await raf.close();
      return null;
    }
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
}

class _UpdateLockHandle {
  const _UpdateLockHandle(this._raf);

  final RandomAccessFile _raf;

  Future<void> release() async {
    try {
      await _raf.unlock();
    } on Object {
      // Ignorado: o handle pode ter sido fechado por encerramento do processo.
    }
    await _raf.close();
  }
}
