import 'dart:async';

import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:flutter/foundation.dart';

/// Provider de UI para o auto update.
///
/// **Por que NAO usa `AsyncStateMixin`** (vs. `architectural_patterns.mdc §2`):
/// o estado de loading/erro vive dentro do `AutoUpdateService` (snapshot
/// continuo, multi-stage, com lock global entre instancias). O provider e'
/// um shim sobre o stream `snapshots`, sem contador local de operacoes
/// concorrentes — adicionar o mixin duplicaria o estado e potencialmente
/// dessincronizaria com o servico (ex.: `isChecking` no provider vs.
/// `_activeCheck != null` no servico).
class AutoUpdateProvider extends ChangeNotifier {
  AutoUpdateProvider({required AutoUpdateService autoUpdateService})
    : _autoUpdateService = autoUpdateService,
      _snapshot = autoUpdateService.snapshot {
    _subscription = _autoUpdateService.snapshots.listen((snapshot) {
      _snapshot = snapshot;
      notifyListeners();
    });
  }

  final AutoUpdateService _autoUpdateService;
  late final StreamSubscription<AppUpdateSnapshot> _subscription;

  AppUpdateSnapshot _snapshot;

  AppUpdateSnapshot get snapshot => _snapshot;
  AppUpdateStatus get status => _snapshot.status;
  bool get isChecking =>
      status == AppUpdateStatus.checking ||
      status == AppUpdateStatus.downloading ||
      status == AppUpdateStatus.installing;
  bool get updateAvailable => _snapshot.updateAvailable;
  DateTime? get lastCheckDate => _snapshot.lastCheckAt;
  DateTime? get lastErrorDate => _snapshot.lastErrorAt;
  String? get error => _snapshot.errorMessage;
  bool get isInitialized => _autoUpdateService.isInitialized;
  String? get feedUrl => _autoUpdateService.feedUrl;
  String? get currentVersion => _snapshot.currentVersion;
  String? get targetVersion => _snapshot.targetVersion;
  String? get statusMessage => _snapshot.message;
  bool get isDisabled => status == AppUpdateStatus.disabled;
  AppUpdateDisabledReason? get disabledReason => _snapshot.disabledReason;

  /// §audit-2026-05-28 wave 4 (UI banner): razão semântica do último
  /// bloqueio (UI usa para escolher banner + ações inline). Só faz
  /// sentido olhar quando `status == blockedByActiveBackup`.
  AppUpdateBlockReason? get blockReason => _snapshot.blockReason;

  /// `true` quando o último bloqueio veio do gate UAC (UI mostra
  /// botão "Atualizar agora" embutido — `manual` passa pelo gate).
  bool get isBlockedByUacPolicy =>
      status == AppUpdateStatus.blockedByActiveBackup &&
      blockReason == AppUpdateBlockReason.uacPolicy;
  AppUpdateStage? get currentStage => _snapshot.stage;
  AppUpdateStage? get lastFailureStage => _snapshot.lastFailureStage;
  AppUpdateSource? get lastSource => _snapshot.lastSource;
  int? get lastAttemptNumber => _snapshot.lastAttemptNumber;
  Duration? get lastDownloadDuration => _snapshot.lastDownloadDuration;
  Duration? get lastCheckDuration => _snapshot.lastCheckDuration;
  String get updateContextPath => AutoUpdateService.updateContextSupportPath();
  String get diagnosticsPath => AutoUpdateService.diagnosticsSupportPath();
  String get lockFilePath => AutoUpdateService.lockFileSupportPath();
  String get configFilePath => AutoUpdateService.configFileSupportPath();

  Future<void> checkForUpdates() {
    return _autoUpdateService.checkNow(source: AppUpdateSource.manual);
  }

  void clearError() {
    _autoUpdateService.clearError();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
