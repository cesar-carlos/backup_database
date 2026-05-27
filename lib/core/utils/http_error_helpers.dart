/// Helpers para mapear strings de erro de APIs HTTP em uma forma
/// resistente a falsos positivos.
///
/// Substitui o anti‑padrão `errorStr.contains('401')` (que matcheia
/// "11401", "id=4011", etc.) por uma detecção com **word‑boundary** de
/// código HTTP de 3 dígitos.
class HttpErrorHelpers {
  HttpErrorHelpers._();

  /// Retorna `true` se `text` contém o `code` HTTP como token isolado
  /// (não cercado por outros dígitos).
  ///
  /// `text` é esperado em **lower case**.
  static bool containsHttpStatus(String text, int code) {
    final pattern = RegExp('(?<![0-9])$code(?![0-9])');
    return pattern.hasMatch(text);
  }

  /// Retorna o primeiro código de `codes` encontrado em `text` (como
  /// token isolado), ou `null` se nenhum encontrado.
  ///
  /// `text` é esperado em **lower case**.
  static int? firstHttpStatusIn(String text, List<int> codes) {
    for (final code in codes) {
      if (containsHttpStatus(text, code)) return code;
    }
    return null;
  }
}
