import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter/foundation.dart';

class AutoUpdateProvider extends ChangeNotifier with AsyncStateMixin {
  AutoUpdateProvider({required AutoUpdateService autoUpdateService})
    : _autoUpdateService = autoUpdateService;
  final AutoUpdateService _autoUpdateService;

  bool _updateAvailable = false;
  DateTime? _lastCheckDate;

  /// Mantido como alias para compatibilidade com a UI atual: a verificação
  /// de atualizações usa o mesmo `isLoading` do mixin.
  bool get isChecking => isLoading;
  bool get updateAvailable => _updateAvailable;
  DateTime? get lastCheckDate => _lastCheckDate;
  bool get isInitialized => _autoUpdateService.isInitialized;
  String? get feedUrl => _autoUpdateService.feedUrl;

  Future<void> checkForUpdates() async {
    if (!_autoUpdateService.isInitialized) {
      setErrorManual('Serviço de atualização não inicializado');
      return;
    }

    await runAsync<void>(
      action: () async {
        await _autoUpdateService.checkForUpdatesManually();
        _lastCheckDate = DateTime.now();
        LoggerService.info('Verificação de atualizações concluída');
      },
    );
    if (error != null) {
      LoggerService.error('Erro ao verificar atualizações: $error');
    }
  }

  void setUpdateAvailable(bool available) {
    _updateAvailable = available;
    notifyListeners();
  }
}
