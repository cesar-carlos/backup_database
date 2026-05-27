import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;

/// Helper to query and validate the Windows Service account configured for
/// the installed service. Centraliza tanto a sondagem do account via
/// PowerShell quanto a política de quais contas suportam atualização
/// silenciosa (`LocalSystem` ou aliases equivalentes).
///
/// S5 da auditoria: agora usa `ProcessService` em vez de `Process.run`
/// direto. Benefícios:
/// - Redaction automática de credenciais em logs (mesmo a query
///   `Win32_Service.StartName` não vaza senha hoje, mas a stack
///   consistente protege contra regressão futura).
/// - Timeout consistente (5s) — antes era unbounded.
/// - Telemetria/logging estruturado quando o probe falha.
/// - Output truncation (5 MB cap) — defesa contra OOM em máquinas
///   onde o powershell.exe trava em loop.
class ServiceAccountProbe {
  ServiceAccountProbe({
    required this.serviceName,
    required ps.ProcessService processService,
  }) : _processService = processService;

  /// Construtor legado para callers que ainda não foram migrados para
  /// receber `ProcessService` via DI. Internamente, instancia um próprio.
  factory ServiceAccountProbe.legacy({required String serviceName}) {
    return ServiceAccountProbe(
      serviceName: serviceName,
      processService: ps.ProcessService(),
    );
  }

  static const String _supportedServiceAccount = 'LocalSystem';
  static const Duration _probeTimeout = Duration(seconds: 5);

  final String serviceName;
  final ps.ProcessService _processService;

  Future<String?> probeInstalledAccount() async {
    final result = await _processService.run(
      executable: 'powershell.exe',
      arguments: <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "(Get-CimInstance Win32_Service -Filter \"Name='$serviceName'\").StartName",
      ],
      timeout: _probeTimeout,
    );

    return result.fold(
      (processResult) {
        if (processResult.exitCode != 0) {
          LoggerService.warning(
            'Falha ao consultar conta do Windows Service para auto update '
            '(exit ${processResult.exitCode}): ${processResult.stderr}',
          );
          return null;
        }
        final account = processResult.stdout.trim();
        return account.isEmpty ? null : account;
      },
      (failure) {
        LoggerService.warning(
          'Erro ao consultar conta do Windows Service para auto update: '
          '$failure',
        );
        return null;
      },
    );
  }

  static bool isSupportedSilentUpdateServiceAccount(String? serviceAccount) {
    final normalized = serviceAccount?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    return normalized == _supportedServiceAccount.toLowerCase() ||
        normalized == 'system' ||
        normalized == r'nt authority\system';
  }

  static String? buildUnsupportedServiceAccountMessage(String? serviceAccount) {
    final normalized = serviceAccount?.trim();
    if (isSupportedSilentUpdateServiceAccount(normalized)) {
      return null;
    }
    if (normalized == null || normalized.isEmpty) {
      return 'Atualização automática silenciosa bloqueada: não foi possível '
          'validar a conta do Windows Service. Reinstale o serviço em '
          'LocalSystem ou execute a atualização manualmente.';
    }
    return 'Atualização automática silenciosa bloqueada: o Windows Service '
        'está configurado com a conta "$normalized". Nesta rodada o '
        'auto update silencioso só é suportado para serviços em '
        'LocalSystem. Atualize manualmente ou reinstale o serviço '
        'com LocalSystem.';
  }
}
