/// Valida campos que vão direto para a connection string Sybase
/// (`ENG=...;DBN=...;UID=...;PWD=...`).
///
/// O parser do Sybase usa `;` como separador de parâmetros e `=` como
/// separador chave/valor. Sem sanitização, um campo contendo qualquer
/// um desses caracteres permite injetar parâmetros adicionais. Exemplos
/// de cenários (acesso à config local):
///
/// - `password = 'x;LOG=hack.log;'` → redireciona o log do servidor.
/// - `username = 'u;DBN=outra_base'` → altera o banco alvo.
/// - `serverName = 'srv;INT=600'` → adiciona timeout.
///
/// `DatabaseName` já proíbe separadores de path/control chars, mas
/// permite `;` e `=` (porque o caso de uso original era nome de
/// arquivo). Esta classe fecha esse gap especificamente para os 4
/// campos que aparecem em connection string Sybase.
///
/// Aplicado no momento do save no `SybaseConfigDialog`. Bases legadas
/// que já têm `;`/`=` permanecem intocadas — quem detecta no caminho
/// de execução é o próprio Sybase (mensagem genérica), mas o caminho
/// novo (save no dialog) bloqueia.
abstract final class SybaseConnectionFieldValidator {
  static const Set<String> _forbiddenChars = {';', '='};

  /// Retorna `null` quando [value] é seguro para interpolar na
  /// connection string Sybase, ou uma mensagem de erro orientada
  /// quando contém algum caractere reservado.
  ///
  /// [fieldName] é usado apenas para a mensagem (ex.: "Senha",
  /// "Nome do servidor").
  static String? validate(String value, String fieldName) {
    for (final ch in _forbiddenChars) {
      if (value.contains(ch)) {
        return '$fieldName não pode conter o caractere "$ch" — é '
            'reservado pelo parser de connection string Sybase '
            '(ex.: `ENG=...;DBN=...`).';
      }
    }
    return null;
  }

  /// Retorna `true` se [value] contém qualquer caractere reservado.
  /// Conveniência para checks early-return fora de validators de Form.
  static bool isUnsafe(String value) {
    for (final ch in _forbiddenChars) {
      if (value.contains(ch)) return true;
    }
    return false;
  }
}
