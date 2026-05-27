import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';

typedef ServiceAccountProbeRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Helper to query and validate the Windows Service account configured for
/// the installed service. Centraliza tanto a sondagem do account via
/// PowerShell quanto a política de quais contas suportam atualização
/// silenciosa (`LocalSystem` ou aliases equivalentes).
class ServiceAccountProbe {
  ServiceAccountProbe({
    required this.serviceName,
    ServiceAccountProbeRunner? processRunner,
  }) : _runProcess = processRunner ?? Process.run;

  static const String _supportedServiceAccount = 'LocalSystem';

  final String serviceName;
  final ServiceAccountProbeRunner _runProcess;

  Future<String?> probeInstalledAccount() async {
    try {
      final result = await _runProcess('powershell.exe', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "(Get-CimInstance Win32_Service -Filter \"Name='$serviceName'\").StartName",
      ]);
      if (result.exitCode != 0) {
        LoggerService.warning(
          'Falha ao consultar conta do Windows Service para auto update: '
          '${result.stderr}',
        );
        return null;
      }
      final account = result.stdout.toString().trim();
      return account.isEmpty ? null : account;
    } on Object catch (e, s) {
      LoggerService.warning(
        'Erro ao consultar conta do Windows Service para auto update',
        e,
        s,
      );
      return null;
    }
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
