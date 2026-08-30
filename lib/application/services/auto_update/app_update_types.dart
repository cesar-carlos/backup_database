import 'dart:io';

import 'package:backup_database/core/config/app_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

abstract final class AppUpdateConstants {
  static const int updateContextSchemaVersion = 2;
  static const Duration updateContextTtl = Duration(minutes: 45);
  static const int diagnosticsSchemaVersion = 1;
  static const Duration defaultLockStaleAfter = Duration(hours: 2);
  static const String updateContextFileName = 'update_context.json';
  static const String updateDiagnosticsFileName = 'auto_update_history.jsonl';
  static const String lockFileName = 'auto_update.lock';
}

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

  /// Falha ao consultar providers de prontidão (ex.: exceção inesperada).
  /// Fail-closed: não arriscar handoff sem saber se há backup ativo.
  readinessCheckUnavailable,
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
  completed;

  String get token {
    return switch (this) {
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

typedef DetachedProcessStarter = Future<DetachedProcessHandle?> Function(
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
typedef InstallReadinessCheck = Future<AppUpdateBlockOutcome?> Function(
  AppcastRelease release,
  AppUpdateSource source,
);
typedef UpdateInstallContextProvider = Future<AppUpdateInstallContext> Function(
  AppcastRelease release,
);
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
           schemaVersion ?? AppUpdateConstants.updateContextSchemaVersion,
       expiresAt =
           expiresAt ?? createdAt.add(AppUpdateConstants.updateContextTtl),
       contextId =
           contextId ??
           '${origin.name}-$targetVersion-'
               '${createdAt.toUtc().millisecondsSinceEpoch}';

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

class BeforeInstallHookTimeoutException implements Exception {
  BeforeInstallHookTimeoutException(this.timeout);

  final Duration timeout;

  @override
  String toString() =>
      'A preparação para a atualização excedeu o tempo limite de '
      '${timeout.inSeconds} segundos. Verifique se há backups ou '
      'transferências em andamento e tente novamente.';
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
