import 'package:backup_database/domain/entities/license.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Contrato para leitura e validação da licença efetiva.
///
/// Distinção importante:
///
/// - [getCurrentLicense] aplica a **política efetiva**: device revogado
///   devolve `Failure`; licença persistida **válida** (premium) tem
///   precedência; se a persistida estiver ausente/expirada/notBefore e
///   o trial full/free ainda estiver ativo, devolve a licença **sintética**
///   de avaliação (não persistida). Após o corte do trial, expirada/
///   ausente devolvem `Failure`. Use isto para gates de feature.
///
/// - [getStoredLicense] devolve a licença persistida sem aplicar
///   expiração/revogação/trial. Use isto para **renderizar o estado** na UI
///   ("Sua licença expirou em X — renove") em paralelo ao trial.
abstract class ILicenseValidationService {
  Future<rd.Result<License>> getCurrentLicense();
  Future<rd.Result<License>> getStoredLicense();
  Future<rd.Result<bool>> isFeatureAllowed(String feature);
}
