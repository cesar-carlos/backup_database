import 'package:backup_database/core/constants/windows_service_constants.dart';

class WindowsServiceMessages {
  WindowsServiceMessages._();

  static const String notSupportedOnPlatform =
      'Windows Service só é suportado no Windows';

  static const String accessDeniedSolution =
      'Solução:\n'
      '1. Feche o aplicativo\n'
      '2. Clique com botão direito no ícone do aplicativo\n'
      '3. Selecione "Executar como administrador"\n'
      '4. Tente novamente';

  static const String troubleshootingAdminLogs =
      'Tente:\n'
      '1. Executar como Administrador\n'
      '2. Verificar logs em ${WindowsServiceConstants.logPath}\n'
      '3. Atualizar o status e tentar novamente';

  static const String troubleshootingWithEnv =
      'Tente:\n'
      '1. Executar como Administrador\n'
      r'2. Verificar se existe C:\ProgramData\BackupDatabase\config\.env'
      '\n'
      '3. Verificar logs em ${WindowsServiceConstants.logPath} '
      '(service_stdout.log, service_stderr.log)\n'
      '4. Atualizar o status e tentar novamente';
}
