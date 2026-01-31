import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter/services.dart';

class ClipboardService {
  ClipboardService();

  Future<bool> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      LoggerService.info('Texto copiado para clipboard');
      return true;
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao copiar para clipboard', e, stackTrace);
      return false;
    }
  }
}
