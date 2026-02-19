import 'dart:io';

import 'package:backup_database/domain/services/i_windows_service_service.dart';

typedef UiSchedulerPolicyWarning = void Function(String message);

enum UiSchedulerFallbackMode { failOpen, failSafe }

class UiSchedulerPolicy {
  UiSchedulerPolicy(
    this._windowsServiceService, {
    bool? isWindows,
    UiSchedulerPolicyWarning? onWarning,
    UiSchedulerFallbackMode fallbackMode = UiSchedulerFallbackMode.failOpen,
  }) : _isWindows = isWindows ?? Platform.isWindows,
       _onWarning = onWarning,
       _fallbackMode = fallbackMode;

  final IWindowsServiceService _windowsServiceService;
  final bool _isWindows;
  final UiSchedulerPolicyWarning? _onWarning;
  final UiSchedulerFallbackMode _fallbackMode;

  Future<bool> shouldSkipSchedulerInUiMode() async {
    if (!_isWindows) {
      return false;
    }

    try {
      final statusResult = await _windowsServiceService.getStatus();

      return statusResult.fold(
        (status) => status.isInstalled && status.isRunning,
        (failure) {
          _onWarning?.call(
            'Nao foi possivel consultar status do servico para decisao de '
            'scheduler: $failure',
          );
          return _shouldSkipOnFailure();
        },
      );
    } on Object catch (e) {
      _onWarning?.call(
        'Falha ao verificar servico do Windows para decisao de scheduler: $e',
      );
      return _shouldSkipOnFailure();
    }
  }

  bool _shouldSkipOnFailure() {
    return _fallbackMode == UiSchedulerFallbackMode.failSafe;
  }
}
