import 'package:flutter/widgets.dart';

class IntegrityUiStrings {
  IntegrityUiStrings._();

  static bool _isPortuguese(Locale locale) =>
      locale.languageCode.toLowerCase() == 'pt';

  static String integrityFailedTitle(Locale locale) {
    if (_isPortuguese(locale)) return 'Falha de integridade';
    return 'Integrity check failed';
  }

  static String integrityInconclusiveTitle(Locale locale) {
    if (_isPortuguese(locale)) return 'Integridade não confirmada';
    return 'Integrity not confirmed';
  }

  static String executeBackupErrorTitle(Locale locale) {
    if (_isPortuguese(locale)) return 'Erro ao Executar Backup';
    return 'Error Running Backup';
  }

  static String integrityFailedMessage(Locale locale, String details) {
    final base = _isPortuguese(locale)
        ? 'Não foi possível garantir a integridade do backup enviado.'
        : 'Unable to guarantee the integrity of the uploaded backup.';
    return _withDetails(locale, base, details);
  }

  static String integrityInconclusiveMessage(Locale locale, String details) {
    final base = _isPortuguese(locale)
        ? 'A verificação de integridade foi inconclusiva.'
        : 'The integrity verification was inconclusive.';
    return _withDetails(locale, base, details);
  }

  static String _withDetails(Locale locale, String base, String details) {
    if (details.trim().isEmpty) {
      return base;
    }
    final detailsLabel = _isPortuguese(locale) ? 'Detalhes' : 'Details';
    return '$base\n$detailsLabel: $details';
  }
}
