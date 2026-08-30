import 'dart:async';

import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';
import 'package:flutter/foundation.dart';

enum NotificationHistoryPeriod {
  last24Hours,
  last7Days,
  last30Days,
  all,
}

class NotificationHistoryLoader {
  NotificationHistoryLoader({
    required this._auditRepository,
    required this._notifyListeners,
    required this._isDisposed,
  });

  final IEmailTestAuditRepository _auditRepository;
  final VoidCallback _notifyListeners;
  final bool Function() _isDisposed;

  List<EmailTestAudit> history = const [];
  String? error;
  bool isLoading = false;
  NotificationHistoryPeriod period = NotificationHistoryPeriod.last7Days;
  String? configIdFilter;
  Timer? _reloadTimer;
  int _loadRequestId = 0;

  void clear() {
    history = const [];
    configIdFilter = null;
    error = null;
  }

  void dispose() {
    _reloadTimer?.cancel();
    _reloadTimer = null;
  }

  void scheduleReload() {
    if (_isDisposed()) {
      return;
    }
    _reloadTimer?.cancel();
    _reloadTimer = Timer(
      const Duration(milliseconds: 300),
      () {
        if (_isDisposed()) {
          return;
        }
        unawaited(load());
      },
    );
  }

  Future<void> setPeriod(NotificationHistoryPeriod next) async {
    if (period == next) {
      return;
    }
    period = next;
    await load();
  }

  Future<void> setConfigFilter(String? configId) async {
    if (configIdFilter == configId) {
      return;
    }
    configIdFilter = configId;
    await load();
  }

  Future<void> load({bool notify = true}) async {
    final requestId = ++_loadRequestId;
    isLoading = true;
    error = null;
    if (notify) {
      _notifyListeners();
    }

    final startAt = resolveStart(period);
    final result = await _auditRepository.getRecent(
      configId: configIdFilter,
      startAt: startAt,
      endAt: DateTime.now(),
      limit: 200,
    );

    if (_isDisposed() || requestId != _loadRequestId) {
      return;
    }

    result.fold(
      (loaded) {
        history = loaded;
        error = null;
      },
      (failure) {
        history = const [];
        error = AsyncStateMixin.extractFailureMessage(failure);
      },
    );

    isLoading = false;
    if (notify) {
      _notifyListeners();
    }
  }

  static DateTime? resolveStart(NotificationHistoryPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case NotificationHistoryPeriod.last24Hours:
        return now.subtract(const Duration(hours: 24));
      case NotificationHistoryPeriod.last7Days:
        return now.subtract(const Duration(days: 7));
      case NotificationHistoryPeriod.last30Days:
        return now.subtract(const Duration(days: 30));
      case NotificationHistoryPeriod.all:
        return null;
    }
  }
}
