import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

bool appLocaleIsPortuguese(Locale locale) =>
    locale.languageCode.toLowerCase() == 'pt';

String appLocaleStringForLocale(Locale locale, String ptBr, String enUs) =>
    appLocaleIsPortuguese(locale) ? ptBr : enUs;

String appLocaleString(BuildContext context, String ptBr, String enUs) {
  return appLocaleStringForLocale(
    Localizations.localeOf(context),
    ptBr,
    enUs,
  );
}

String appLocaleLastUpdateCheckSubtitle(BuildContext context, DateTime date) {
  if (appLocaleIsPortuguese(Localizations.localeOf(context))) {
    return 'Última verificação: '
        '${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(date)}';
  }
  return 'Last check: '
      '${DateFormat('M/d/yyyy h:mm a', 'en_US').format(date)}';
}

Locale appLocaleFromPlatform() => PlatformDispatcher.instance.locale;
