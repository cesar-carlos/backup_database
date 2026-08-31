import 'dart:io';

import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class WindowsServiceEnvProvisioner {
  const WindowsServiceEnvProvisioner();

  /// Garante que `%ProgramData%\BackupDatabase\config\.env` exista antes
  /// da instalação. Anteriormente o preflight apenas avisava e prosseguia,
  /// mas o serviço subseqüentemente falhava em `EnvironmentLoader`,
  /// `exit(1)`, e o NSSM reiniciava em loop a cada 60s — invisível na UI
  /// (issue §2.2 da auditoria).
  ///
  /// Estratégia: se `.env` já existe, no-op. Caso contrário, tenta copiar
  /// `<appDir>\.env`, `<appDir>\.env.example` ou
  /// `<configDir>\.env.example` (template do Inno em ProgramData). Se nada
  /// estiver disponível, retorna `ValidationFailure` bloqueante com
  /// instrução acionável ao usuário.
  ///
  /// O parâmetro [configDirOverride] é exclusivamente para testes — em
  /// produção sempre usa `%ProgramData%\BackupDatabase\config`. Testes
  /// unitários injetam um diretório temporário para evitar side-effects
  /// no sistema.
  Future<rd.Result<void>> ensureServiceEnvFile({
    required String appDir,
    String? configDirOverride,
  }) async {
    final configDir = configDirOverride ?? _defaultServiceConfigDir();
    final envPath = '$configDir${Platform.pathSeparator}.env';
    final envFile = File(envPath);
    if (await envFile.exists()) {
      return const rd.Success(unit);
    }

    try {
      Directory(configDir).createSync(recursive: true);
    } on Object catch (e) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Não foi possível criar diretório de configuração '
              '$configDir: $e\n\n'
              'Tente executar como Administrador.',
        ),
      );
    }

    final candidates = [
      File(p.join(appDir, '.env')),
      File(p.join(appDir, '.env.example')),
      File(p.join(configDir, '.env.example')),
    ];
    var hadCandidate = false;
    Object? lastCopyError;
    for (final candidate in candidates) {
      if (await candidate.exists()) {
        hadCandidate = true;
        try {
          await candidate.copy(envPath);
          LoggerService.info(
            'Copiado ${candidate.path} → $envPath para uso do serviço',
          );
          return const rd.Success(unit);
        } on Object catch (e) {
          lastCopyError = e;
          LoggerService.warning(
            'Falha ao copiar ${candidate.path} para $envPath: $e',
          );
        }
      }
    }

    if (hadCandidate) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Não foi possível copiar o template .env para $envPath: '
              '$lastCopyError\n\n'
              'Tente executar como Administrador.',
        ),
      );
    }

    return rd.Failure(
      ValidationFailure(
        message:
            'Arquivo .env não encontrado em $envPath e nenhum '
            'template (.env / .env.example) está disponível em $appDir '
            'nem em $configDir.\n\n'
            'Crie manualmente o arquivo $envPath com a configuração do '
            'serviço antes de instalar. Sem ele, o serviço entra em loop '
            'de restart silencioso após instalado.',
      ),
    );
  }

  String _defaultServiceConfigDir() => WindowsServiceConstants.configPath;
}
