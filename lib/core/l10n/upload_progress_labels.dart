import 'package:flutter/material.dart';

/// Localizes upload progress messages based on locale.
///
/// Messages from the backend are in Portuguese. This helper translates
/// them for display when the app locale is not Portuguese.
class UploadProgressLabels {
  const UploadProgressLabels._();

  static String localizeMessage(String message, Locale locale) {
    if (locale.languageCode.toLowerCase() == 'pt') {
      return message;
    }
    return _translateToEnglish(message);
  }

  static String _translateToEnglish(String message) {
    const translations = [
      ('Enviando para FTP: ', 'Uploading to FTP: '),
      ('Enviando para Google Drive: ', 'Uploading to Google Drive: '),
      ('Enviando para Dropbox: ', 'Uploading to Dropbox: '),
      ('Enviando para Nextcloud: ', 'Uploading to Nextcloud: '),
      ('Copiando para pasta local: ', 'Copying to local folder: '),
      ('Preparando cópia para pasta local: ', 'Preparing copy to local folder: '),
      ('Retomando de ', 'Resuming from '),
      (' concluído ✓', ' completed ✓'),
      (' destinos: ', ' destinations: '),
      ('Enviando para ', 'Uploading to '),
    ];
    var result = message;
    for (final (from, to) in translations) {
      result = result.replaceAll(from, to);
    }
    return result;
  }
}
