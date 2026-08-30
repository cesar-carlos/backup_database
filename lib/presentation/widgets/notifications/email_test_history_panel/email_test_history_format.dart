import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

class EmailTestHistoryFormat {
  EmailTestHistoryFormat._();

  static String formatCreatedAt(BuildContext context, DateTime date) {
    if (appLocaleIsPortuguese(Localizations.localeOf(context))) {
      return DateFormat('dd/MM/yyyy HH:mm:ss', 'pt_BR').format(date);
    }
    return DateFormat('M/d/yyyy h:mm:ss a', 'en_US').format(date);
  }

  static String pluralizedAttemptLabel(BuildContext context, int count) {
    if (appLocaleIsPortuguese(Localizations.localeOf(context))) {
      return count == 1 ? '1 tentativa' : '$count tentativas';
    }
    return count == 1 ? '1 attempt' : '$count attempts';
  }

  static String mostTestedRecipient(
    BuildContext context,
    List<EmailTestAudit> history,
  ) {
    if (history.isEmpty) {
      return appLocaleString(context, 'Não disponível', 'Unavailable');
    }

    final counters = <String, int>{};
    for (final entry in history) {
      counters.update(
        entry.recipientEmail,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    final winner = counters.entries.reduce(
      (best, current) => current.value > best.value ? current : best,
    );
    return winner.key;
  }
}
