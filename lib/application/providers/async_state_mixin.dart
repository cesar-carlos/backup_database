import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter/foundation.dart';

/// Mixin para `ChangeNotifier`s da camada de application que precisam
/// expor estado assíncrono padrão (`isLoading`, `error`, `lastErrorCode`)
/// para a UI.
///
/// Antes desta classe, cada provider duplicava o boilerplate:
///
/// ```dart
/// _isLoading = true; _error = null; notifyListeners();
/// try {
///   final result = await op();
///   result.fold((s) { _x = s; _isLoading = false; notifyListeners(); },
///              (f) { _error = f.message; _isLoading = false; notifyListeners(); });
/// } on Object catch (e) {
///   _error = '...$e'; _isLoading = false; notifyListeners();
/// }
/// ```
///
/// Em ~15 providers × ~4 métodos = ~200 linhas duplicadas, com
/// vulnerabilidades reais:
///   - **race em `_isLoading`** quando duas operações concorrentes
///     terminavam em ordem inversa;
///   - `notifyListeners()` fora de `try/finally` deixava listeners com
///     estado inconsistente caso algo lançasse no meio;
///   - `failure as Failure` sem `is` causava crash quando vinha outro
///     tipo de exceção.
///
/// Este mixin centraliza tudo via [runAsync], que:
///   - usa **contador atômico** ao invés de boolean para `isLoading`,
///     resolvendo o race;
///   - garante `notifyListeners()` em `try/finally`;
///   - extrai mensagem amigável de qualquer `Object` via [extractFailureMessage].
mixin AsyncStateMixin on ChangeNotifier {
  /// Contador de operações em curso. Usar contador em vez de boolean
  /// resolve o race em que `op A` (`_isLoading=false`) terminava antes
  /// de `op B`, deixando a UI achando que tudo terminou.
  int _runningOperations = 0;
  String? _error;
  String? _lastErrorCode;

  bool get isLoading => _runningOperations > 0;
  String? get error => _error;
  String? get lastErrorCode => _lastErrorCode;

  /// Limpa a mensagem de erro atual e notifica listeners. Substitui
  /// implementações idênticas que existiam em ~12 providers.
  void clearError() {
    if (_error == null && _lastErrorCode == null) return;
    _error = null;
    _lastErrorCode = null;
    notifyListeners();
  }

  /// Helper para extrair mensagem amigável de qualquer `Object`.
  /// Antes era reimplementado inline com `failure as Failure` (cast
  /// direto, crashava com tipos inesperados).
  static String extractFailureMessage(Object failure) {
    if (failure is Failure) return failure.message;
    return failure.toString();
  }

  /// Helper para extrair `code` de uma `Failure`. Retorna `null` para
  /// qualquer outro tipo.
  static String? extractFailureCode(Object? failure) {
    if (failure is Failure) return failure.code;
    return null;
  }

  /// Executa [action] gerenciando `isLoading` e `error` automaticamente.
  ///
  /// - Incrementa o contador de operações ao iniciar (notifica listeners
  ///   uma vez se passou de 0 → 1).
  /// - Decrementa no `finally`. Listeners são notificados na transição
  ///   1 → 0 (e sempre quando há mudança em `_error`).
  /// - Captura qualquer exception, formata via [genericErrorMessage] +
  ///   exception, marca em `_error` e re-throw NÃO é feito por padrão
  ///   (use [rethrowOnError] = true para customizar). Em vez disso,
  ///   `runAsync` retorna `null` em caso de erro, o que dá ao caller
  ///   um sinal limpo para retornar `false` ao usuário sem precisar de
  ///   try/catch externo.
  Future<T?> runAsync<T>({
    required Future<T> Function() action,
    String? genericErrorMessage,
    bool rethrowOnError = false,
  }) async {
    _runningOperations++;
    final wasIdle = _runningOperations == 1;
    final hadError = _error != null;
    if (wasIdle || hadError) {
      _error = null;
      _lastErrorCode = null;
      notifyListeners();
    }

    try {
      return await action();
    } on Object catch (e, s) {
      _error = genericErrorMessage != null
          ? '$genericErrorMessage: ${extractFailureMessage(e)}'
          : extractFailureMessage(e);
      _lastErrorCode = extractFailureCode(e);
      LoggerService.warning(
        '[AsyncStateMixin] runAsync caught error: $e',
        e,
        s,
      );
      if (rethrowOnError) rethrow;
      return null;
    } finally {
      _runningOperations--;
      // Garante notify mesmo se `notifyListeners` lançar (raro mas
      // defensivo) — não temos try/catch aqui pois Dart `finally`
      // já protege a saída do método.
      notifyListeners();
    }
  }

  /// Marca um erro manualmente (sem executar uma operação assíncrona).
  /// Útil para validações sincrônas no provider.
  @protected
  void setErrorManual(String message, {String? code}) {
    _error = message;
    _lastErrorCode = code;
    notifyListeners();
  }
}
