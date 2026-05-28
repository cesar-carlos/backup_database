import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_revocation_checker.dart';

/// Helper compartilhado entre `LicenseValidationService` (fluxo de
/// leitura) e `LicenseGenerationService.createLicenseFromKey` (fluxo de
/// cadastro). Centraliza o fail-open observável da checagem de
/// revogação.
///
/// **Por quê fail-open?** Se o `IRevocationChecker` estiver `null` ou
/// lançar (ex.: arquivo de revogação temporariamente inacessível),
/// fail-closed quebraria todos os backups da máquina — pior UX que o
/// risco residual de aceitar uma licença efetivamente revogada por
/// alguns minutos enquanto a fonte é restaurada.
///
/// **Por quê centralizar?** Antes, o cadastro de licença em
/// `createLicenseFromKey` usava `?? false` sem log (silent fail-open) e
/// o fluxo de leitura usava `_checkRevokedSafely` (log + observável).
/// As duas implementações divergiam — atacante poderia escolher o
/// caminho mais fraco. Agora ambas usam o mesmo helper.
class RevocationCheckHelper {
  RevocationCheckHelper._();

  /// Consulta o [checker] de forma defensiva. Retorna:
  /// - `true`  → device está na lista de revogação.
  /// - `false` → device não está revogado *ou* checker null/erro.
  ///
  /// Erros são logados como warning/error (não engolidos em silêncio).
  static Future<bool> isRevokedSafe(
    IRevocationChecker? checker,
    String deviceKey, {
    String? caller,
  }) async {
    final tag = caller != null ? ' [$caller]' : '';
    if (checker == null) {
      LoggerService.warning(
        'IRevocationChecker não configurado$tag — assumindo licença não '
        'revogada (fail-open). Configure '
        'BACKUP_DATABASE_LICENSE_REVOCATION_LIST(_PATH) em produção.',
      );
      return false;
    }
    try {
      return await checker.isRevoked(deviceKey);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Falha ao consultar revocation checker$tag — assumindo licença '
        'não revogada (fail-open). Investigue a causa.',
        e,
        stackTrace,
      );
      return false;
    }
  }
}
