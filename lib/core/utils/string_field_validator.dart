import 'package:backup_database/core/errors/failure.dart';

/// Helpers para validação de campos string obrigatórios em use cases.
///
/// **Por que existe**: a sequência de 5 linhas
///
/// ```dart
/// if (config.serverName.trim().isEmpty) {
///   return const rd.Failure(
///     ValidationFailure(message: 'Servidor não pode ser vazio'),
///   );
/// }
/// ```
///
/// estava duplicada em ~8 use cases (Sybase/SQL Server backup,
/// create/update/delete schedule, execute_scheduled_backup,
/// `DestinationUseCase.notEmptyOrFailure`, etc.). Centraliza aqui a
/// frase canônica (`'<label> não pode ser vazio'`) e a regra de
/// considerar trim-vazio como inválido.
///
/// **Retorno**: `ValidationFailure?` (null = OK) — o caller embrulha
/// em `rd.Failure(...)` do tipo certo. Esse formato evita acoplar o
/// helper a generics complicados de `Result<T>`.
class StringFieldValidator {
  StringFieldValidator._();

  /// Verifica que [value] não é null nem branco (após `trim`). Retorna
  /// `null` quando válido, ou [ValidationFailure] com mensagem
  /// `'<fieldLabel> não pode ser vazio'`.
  static ValidationFailure? requireNonBlank({
    required String? value,
    required String fieldLabel,
  }) {
    if (value == null || value.trim().isEmpty) {
      return ValidationFailure(message: '$fieldLabel não pode ser vazio');
    }
    return null;
  }

  /// Valida múltiplos campos de uma vez. Retorna o **primeiro**
  /// [ValidationFailure] encontrado (na ordem de iteração do mapa) ou
  /// `null` se todos são válidos.
  ///
  /// **Por que retorna só o primeiro** (em vez de acumular): a UI
  /// existente sempre exibe um único erro por vez, então acumular não
  /// adicionaria valor — e mudar o formato quebraria os call-sites
  /// que hoje fazem `if (failure != null) return rd.Failure(failure);`.
  ///
  /// Use com map literal para preservar ordem:
  /// ```dart
  /// final f = StringFieldValidator.requireAllNonBlank({
  ///   'Servidor': config.server,
  ///   'Nome do banco': config.databaseValue,
  ///   'Diretório de saída': outputDirectory,
  /// });
  /// if (f != null) return rd.Failure(f);
  /// ```
  static ValidationFailure? requireAllNonBlank(
    Map<String, String?> fieldsByLabel,
  ) {
    for (final entry in fieldsByLabel.entries) {
      final failure = requireNonBlank(
        value: entry.value,
        fieldLabel: entry.key,
      );
      if (failure != null) return failure;
    }
    return null;
  }
}
