/// Exit codes used by the application to communicate outcomes to external
/// monitors (Windows Task Scheduler, NSSM, Nagios/Zabbix).
///
/// Centralize-os aqui para garantir que cada código tenha um significado
/// único — antes estavam espalhados entre arquivos de bootstrap e era
/// fácil reusar `1` para falhas conceitualmente distintas.
abstract final class ScheduledBackupExitCode {
  static const int success = 0;
  static const int genericFailure = 1;
  static const int invalidScheduleId = 2;

  /// The mutex owner exists, but its pipe never answered PONG.
  /// Distinct from [genericFailure], which is a backup that already failed.
  static const int ownerNotOnPipe = 3;
}

abstract final class ServiceModeExitCode {
  /// SCM/NSSM stop after cleanup. `exit` ends the process; the service
  /// runner only leaves its message loop on `WM_QUIT`, which nothing posts.
  static const int gracefulShutdown = 0;
  static const int lockDenied = 77;
  static const int fatalBootstrapError = 1;

  /// Usado pelo `AutoUpdateService` quando o serviço encerra para entregar
  /// o controle ao instalador silencioso. Mapeado em `nssm AppExit 78 Exit`
  /// (via `install_service.ps1`/`restore_update_state.ps1`) para impedir
  /// que o NSSM tente reiniciar o serviço enquanto o `setup.iss` ainda está
  /// substituindo os binários — evita race com `AppRestartDelay`.
  ///
  /// O `setup.iss` ainda chama `StopService` no `InitializeSetup`, mas esse
  /// exit code é a defesa-em-profundidade: mesmo se o stop falhar, o NSSM
  /// não reinicia o processo morto.
  static const int handoffForInstaller = 78;
}

abstract final class UiBootstrapExitCode {
  /// Normal UI shutdown **and** a handled second instance (manual or
  /// `--launch-origin=windows-startup`). The Windows runner is already in
  /// `GetMessage`; without `exit(0)` the duplicate process stays alive.
  /// The smoke script `windows_single_instance_smoke.ps1` asserts this 0.
  static const int success = 0;
  static const int fatalBootstrapError = 1;
}
