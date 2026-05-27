import 'package:backup_database/core/utils/string_field_validator.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Abstract base class for destination upload use cases.
///
/// Não força uma assinatura única em `execute` (os destinos têm
/// parâmetros bem distintos: FTP precisa de `runId`/`destinationId`, o
/// upload local não precisa de `isCancelled`, etc.). Em vez disso, expõe
/// helpers de validação (`validateParams`, `validateConfig`,
/// `notEmptyOrFailure`) que os use cases concretos chamam no início,
/// eliminando a duplicação de "if (sourceFilePath.isEmpty) return
/// Failure(ValidationFailure(...));" que existia em 5 lugares.
abstract class DestinationUseCase<TConfig, TResult extends Object> {
  Future<rd.Result<TResult>> execute({
    required String sourceFilePath,
    required TConfig config,
    String? customFileName,
  });

  /// Validates common parameters for destination uploads.
  ///
  /// Verifica que `sourceFilePath` é não-vazio e delega a validação
  /// específica do config para `validateConfig`.
  rd.Result<void> validateParams(String sourceFilePath, TConfig config) {
    final pathFailure = notEmptyOrFailure(
      sourceFilePath,
      'Caminho do arquivo de origem',
    );
    if (pathFailure.isError()) return pathFailure;

    return validateConfig(config);
  }

  /// Override in subclasses to validate config-specific parameters.
  rd.Result<void> validateConfig(TConfig config) {
    return const rd.Success(());
  }

  /// Helper for "campo X não pode ser vazio" — retorna `Failure` se
  /// `value` for vazio/whitespace, ou `Success` caso contrário.
  ///
  /// Delega para [StringFieldValidator.requireNonBlank] (lib/core/utils)
  /// e mantém a forma `Result<void>` aqui porque os subclasses de
  /// `DestinationUseCase` já consomem `Result<void>` em
  /// `validateConfig` — trocar a assinatura aqui forçaria refactor em
  /// cada destination use case concreto.
  static rd.Result<void> notEmptyOrFailure(String value, String fieldLabel) {
    final failure = StringFieldValidator.requireNonBlank(
      value: value,
      fieldLabel: fieldLabel,
    );
    return failure != null ? rd.Failure(failure) : const rd.Success(());
  }
}
