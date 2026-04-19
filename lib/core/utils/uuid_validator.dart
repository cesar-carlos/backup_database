/// Validações simples de UUIDs (versão 1-5) usadas em entradas externas
/// como `--schedule-id=<uuid>` da linha de comando do `Task Scheduler`.
class UuidValidator {
  UuidValidator._();

  // Aceita maiúsculas/minúsculas; valida o formato 8-4-4-4-12 padrão.
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// Retorna `true` quando [value] é um UUID v1–v5 não-vazio.
  static bool isValid(String value) {
    if (value.isEmpty) return false;
    return _uuidPattern.hasMatch(value);
  }
}
