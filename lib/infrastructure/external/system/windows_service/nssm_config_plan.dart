import 'package:backup_database/core/constants/windows_service_constants.dart';

/// Plano declarativo das chaves NSSM que o serviço precisa configurar.
///
/// Centraliza a configuração para evitar divergência entre os 3 caminhos
/// de instalação (`WindowsServiceNssmConfigurator` na UI direta,
/// `WindowsServiceElevationInstaller` via UAC, e `installer/install_service.ps1`).
/// Antes da extração, a instalação via UI esquecia `AppExit 78 Exit` e
/// `AppNoConsole 1`, quebrando o auto-update silencioso (issue §2.1 da auditoria).
class NssmConfigPlan {
  const NssmConfigPlan(this.entries);

  final List<NssmConfigEntry> entries;

  factory NssmConfigPlan.build({
    required String appDir,
    required String logPath,
  }) {
    return NssmConfigPlan([
      const NssmConfigEntry(
        key: 'AppParameters',
        values: ['--mode=server --minimized --run-as-service'],
        critical: true,
      ),
      NssmConfigEntry(
        key: 'AppDirectory',
        values: [appDir],
        critical: true,
      ),
      const NssmConfigEntry(
        key: 'AppEnvironmentExtra',
        values: ['SERVICE_MODE=server'],
        critical: true,
      ),
      const NssmConfigEntry(
        key: 'DisplayName',
        values: [WindowsServiceConstants.displayName],
      ),
      const NssmConfigEntry(
        key: 'Description',
        values: [WindowsServiceConstants.description],
      ),
      const NssmConfigEntry(
        key: 'Start',
        values: ['SERVICE_AUTO_START'],
      ),
      const NssmConfigEntry(
        key: 'AppNoConsole',
        values: ['1'],
        critical: true,
      ),
      NssmConfigEntry(
        key: 'AppStdout',
        values: ['$logPath\\service_stdout.log'],
        critical: true,
      ),
      NssmConfigEntry(
        key: 'AppStderr',
        values: ['$logPath\\service_stderr.log'],
        critical: true,
      ),
      const NssmConfigEntry(
        key: 'AppExit',
        values: ['Default', 'Restart'],
      ),
      const NssmConfigEntry(
        key: 'AppExit',
        values: ['77', 'Exit'],
        critical: true,
      ),
      const NssmConfigEntry(
        key: 'AppExit',
        values: ['78', 'Exit'],
        critical: true,
      ),
      const NssmConfigEntry(
        key: 'AppRestartDelay',
        values: ['60000'],
      ),
    ]);
  }

  List<List<String>> installCommandsFor(String serviceName) =>
      entries.map((e) => e.arguments(serviceName)).toList();

  /// Gera `nssm set` para o script PowerShell elevado, usando
  /// `Set-NssmKeyWithRetry` nas chaves [NssmConfigEntry.critical] e
  /// `Set-NssmKeyOptional` nas demais.
  String toElevatedPowerShellSets() {
    final buffer = StringBuffer();
    for (final entry in entries) {
      final valuesLiteral = entry.values.map(_psSingleQuoted).join(', ');
      final fn = entry.critical
          ? 'Set-NssmKeyWithRetry'
          : 'Set-NssmKeyOptional';
      buffer.writeln(
        '$fn -KeyName "${entry.key}" -Values @($valuesLiteral)',
      );
    }
    return buffer.toString();
  }

  static String _psSingleQuoted(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }
}

class NssmConfigEntry {
  const NssmConfigEntry({
    required this.key,
    required this.values,
    this.critical = false,
  });

  final String key;
  final List<String> values;
  final bool critical;

  List<String> arguments(String serviceName) => [
    'set',
    serviceName,
    key,
    ...values,
  ];
}
