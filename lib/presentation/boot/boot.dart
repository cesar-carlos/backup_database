// Barrel para a camada de boot. Permite consumidores (testes, fluxos
// alternativos de bootstrap) importarem todos os componentes de
// inicialização com um único import.
export 'app_bootstrap.dart';
export 'app_cleanup.dart';
export 'app_initializer.dart';
export 'bootstrap_config.dart';
export 'bootstrap_error_policy.dart';
export 'ipc_server_startup_task.dart';
export 'launch_bootstrap_context.dart';
export 'scheduled_backup_executor.dart';
export 'service_account_probe.dart';
export 'service_auto_update_configurator.dart';
export 'service_bootstrap_log.dart';
export 'service_bootstrap_step_runner.dart';
export 'service_mode_initializer.dart';
export 'service_shutdown_callbacks.dart';
export 'single_instance_checker.dart';
export 'socket_server_startup_task.dart';
export 'temporary_backup_cleanup_startup_task.dart';
export 'tray_manager_startup_task.dart';
export 'ui_scheduler_policy.dart';
export 'ui_scheduler_startup_task.dart';
export 'window_manager_startup_task.dart';
