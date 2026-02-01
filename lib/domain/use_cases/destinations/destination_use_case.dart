import 'package:backup_database/core/errors/failure.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Abstract base class for destination upload use cases
/// Reduces code duplication across destination use cases
abstract class DestinationUseCase<TConfig, TResult extends Object> {
  Future<rd.Result<TResult>> execute({
    required String sourceFilePath,
    required TConfig config,
    String? customFileName,
  });

  /// Validates common parameters for destination uploads
  rd.Result<void> validateParams(String sourceFilePath, TConfig config) {
    if (sourceFilePath.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Caminho do arquivo de origem não pode ser vazio'),
      );
    }

    return validateConfig(config);
  }

  /// Override in subclasses to validate config-specific parameters
  rd.Result<void> validateConfig(TConfig config) {
    return const rd.Success(());
  }
}
