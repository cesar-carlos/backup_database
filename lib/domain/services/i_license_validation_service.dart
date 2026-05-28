import 'package:backup_database/domain/entities/license.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Contrato para leitura e validação da licença ativa.
///
/// Distinção importante:
///
/// - [getCurrentLicense] aplica a **política completa** — expirada,
///   revogada, ou ausente devolvem `Failure`. Use isto para gates de
///   feature e decisões de execução de backup.
///
/// - [getStoredLicense] devolve a licença persistida sem aplicar
///   expiração/revogação. Use isto para **renderizar o estado** na UI
///   ("Sua licença expirou em X — renove"). Antes dessa separação, a UI
///   só conseguia mostrar "Sem licença" para qualquer falha de validação,
///   mesmo quando uma licença válida-mas-expirada estava persistida.
abstract class ILicenseValidationService {
  Future<rd.Result<License>> getCurrentLicense();
  Future<rd.Result<License>> getStoredLicense();
  Future<rd.Result<bool>> isFeatureAllowed(String feature);
}
