/// Constantes centralizadas do Windows Service.
///
/// Antes da consolidação (S12 da auditoria), os mesmos literais
/// (`BackupDatabaseService`, `Backup Database Service`, descrição com
/// SGBDs) apareciam duplicados em 6 lugares:
/// - `infrastructure/external/system/windows_service_service.dart`
/// - `presentation/boot/service_mode_initializer.dart`
/// - `installer/install_service.ps1`
/// - `installer/uninstall_service.ps1`
/// - `installer/restore_update_state.ps1`
/// - `installer/capture_update_context.ps1`
///
/// Agora os locais Dart referenciam esta classe. Para os scripts
/// PowerShell, mantemos o param default e um teste que extrai o default
/// e compara com [WindowsServiceConstants.serviceName] (em
/// `update_installer_scripts_test.dart`).
abstract final class WindowsServiceConstants {
  /// Nome do serviço registrado no Windows Service Manager.
  /// **Não alterar sem migration**: serviços existentes em produção
  /// continuariam registrados sob o nome antigo.
  static const String serviceName = 'BackupDatabaseService';

  /// Nome amigável exibido no Services.msc.
  static const String displayName = 'Backup Database Service';

  /// Descrição do serviço — lista os 4 SGBDs suportados para que clientes
  /// reconheçam o que o serviço faz quando inspecionam o painel de
  /// serviços do Windows.
  static const String description =
      'Servico de backup automatico para SQL Server, '
      'Sybase, PostgreSQL e Firebird';

  /// Diretório padrão de logs do serviço (em ProgramData para sobreviver
  /// reinstalações e ser legível por administradores).
  static const String logPath = r'C:\ProgramData\BackupDatabase\logs';

  /// Diretório padrão de configuração do serviço.
  static const String configPath = r'C:\ProgramData\BackupDatabase\config';
}
