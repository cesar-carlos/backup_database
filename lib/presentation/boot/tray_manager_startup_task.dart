import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';

class TrayManagerStartupTask {
  const TrayManagerStartupTask({
    required this.isTrayEnabled,
    required this.trayDisabledLabel,
    required this.initializeTray,
    required this.logWarning,
  });

  final bool Function() isTrayEnabled;
  final String Function() trayDisabledLabel;
  final Future<void> Function() initializeTray;
  final BootstrapLogWithError logWarning;

  Future<void> start() async {
    if (!isTrayEnabled()) {
      logWarning(
        'Tray icon omitido (compatibilidade): ${trayDisabledLabel()}',
      );
      return;
    }

    try {
      await initializeTray();
    } on Object catch (e, stackTrace) {
      logWarning('Erro ao inicializar tray manager: $e', e, stackTrace);
    }
  }
}
