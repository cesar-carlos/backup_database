import 'dart:async';

import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:flutter/foundation.dart';

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
