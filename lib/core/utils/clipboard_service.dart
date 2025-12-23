import 'package:flutter/services.dart';

import 'logger_service.dart';

class ClipboardService {
  ClipboardService();

  Future<bool> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      LoggerService.info('Texto copiado para clipboard');
      return true;
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao copiar para clipboard', e, stackTrace);
      return false;
    }
  }
}
