import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:result_dart/result_dart.dart' as rd;

/// Helpers genéricos para repositórios baseados em `Result<T>`.
///
/// **Problema que resolve**
/// Antes desta classe, todo método de repositório repetia o boilerplate:
///
/// ```dart
/// try {
///   final value = await dao.something();
///   return rd.Success(value);
/// } on Object catch (e, st) {
///   LoggerService.error('Erro ao ...', e, st);
///   return rd.Failure(DatabaseFailure(
///     message: 'Erro ao ...: $e',
///     originalError: e,
///   ));
/// }
/// ```
///
/// Isso aparecia em ~6 métodos × 5+ repositórios = ~30 cópias do mesmo
/// padrão. Mudanças no shape de `DatabaseFailure` (ex.: adicionar
/// `originalError`) precisavam ser propagadas manualmente em todos os
/// pontos, e a maioria das cópias não logava o stack trace original.
///
/// **Como usar**
/// ```dart
/// Future<rd.Result<List<SqlServerConfig>>> getAll() {
///   return RepositoryGuard.run(
///     errorMessage: 'Erro ao buscar configurações',
///     action: () async {
///       final rows = await dao.getAll();
///       return [for (final r in rows) await _toEntity(r)];
///     },
///   );
/// }
/// ```
///
/// O helper sempre captura o stack trace, registra como `error` no
/// `LoggerService`, e propaga `originalError` para preservar o tipo
/// exato da exception original (útil em diagnósticos).
class RepositoryGuard {
  RepositoryGuard._();

  /// Executa [action] e converte qualquer exception em `Failure`.
  ///
  /// - [errorMessage] é o prefixo da mensagem amigável (sem ":" no final).
  /// - [logErrors] permite desabilitar logging em casos onde o caller
  ///   prefere logar manualmente com contexto adicional.
  /// - [failureBuilder] permite customizar o tipo de `Failure` retornado
  ///   (default: `DatabaseFailure`). Útil para repositórios que precisam
  ///   distinguir falhas de I/O, rede etc.
  static Future<rd.Result<T>> run<T extends Object>({
    required String errorMessage,
    required Future<T> Function() action,
    bool logErrors = true,
    Failure Function(String message, Object originalError)? failureBuilder,
  }) async {
    try {
      final value = await action();
      return rd.Success(value);
    } on Failure catch (failure, st) {
      // Pass-through: quando o `action` lança um `Failure` semântico (ex.:
      // `ValidationFailure` para regras de negócio, `NotFoundFailure` para
      // 404), preservamos o tipo. Sem este branch, o `RepositoryGuard`
      // reembrulharia em `DatabaseFailure`, perdendo a semântica.
      // O log continua acontecendo em nível `warning` (não `error`) porque
      // semanticamente é um caso esperado, não um defeito.
      if (logErrors) {
        LoggerService.warning(
          '$errorMessage (failure semântico): ${failure.message}',
          failure,
          st,
        );
      }
      return rd.Failure(failure);
    } on Object catch (e, st) {
      if (logErrors) {
        LoggerService.error(errorMessage, e, st);
      }
      final failure = failureBuilder != null
          ? failureBuilder('$errorMessage: $e', e)
          : DatabaseFailure(message: '$errorMessage: $e', originalError: e);
      return rd.Failure(failure);
    }
  }

  /// Variante para operações que não retornam valor (retorno `void` no
  /// callback). Usa `Unit` internamente para satisfazer o constraint
  /// `T extends Object` do `result_dart`.
  static Future<rd.Result<Unit>> runVoid({
    required String errorMessage,
    required Future<void> Function() action,
    bool logErrors = true,
    Failure Function(String message, Object originalError)? failureBuilder,
  }) {
    return run<Unit>(
      errorMessage: errorMessage,
      logErrors: logErrors,
      failureBuilder: failureBuilder,
      action: () async {
        await action();
        return unit;
      },
    );
  }
}
