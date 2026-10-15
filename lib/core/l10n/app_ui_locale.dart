import 'dart:io';

import 'package:flutter/widgets.dart';

const Locale appUiLocalePortuguese = Locale('pt', 'BR');
const Locale appUiLocaleEnglish = Locale('en', 'US');

const List<Locale> appSupportedUiLocales = <Locale>[
  appUiLocalePortuguese,
  Locale('pt'),
  appUiLocaleEnglish,
  Locale('en'),
];

const String _defaultProgramData = r'C:\ProgramData';

Locale resolveAppUiLocale({
  required String platformLocaleName,
  String? installerCode,
}) {
  return localeFromUiCode(installerCode) ??
      localeFromUiCode(platformLocaleName) ??
      appUiLocaleEnglish;
}

Locale? localeFromUiCode(String? raw) {
  if (raw == null) {
    return null;
  }
  final code = raw.trim().toLowerCase().replaceAll('_', '-');
  if (code.isEmpty) {
    return null;
  }
  if (code == 'pt' || code.startsWith('pt-') || code == 'brazilianportuguese') {
    return appUiLocalePortuguese;
  }
  if (code == 'en' || code.startsWith('en-') || code == 'english') {
    return appUiLocaleEnglish;
  }
  return null;
}

String installedUiLocaleFilePath({String? programData}) {
  final root =
      programData ?? Platform.environment['ProgramData'] ?? _defaultProgramData;
  return '$root\\BackupDatabase\\config\\ui_locale';
}

String? readInstalledUiLocaleCode({String? path}) {
  final file = File(path ?? installedUiLocaleFilePath());
  try {
    if (!file.existsSync()) {
      return null;
    }
    final code = file.readAsStringSync().trim();
    if (code.isEmpty) {
      return null;
    }
    return code;
  } on Object {
    return null;
  }
}

Locale resolveInstalledAppUiLocale() {
  return resolveAppUiLocale(
    installerCode: readInstalledUiLocaleCode(),
    platformLocaleName: Platform.localeName,
  );
}
