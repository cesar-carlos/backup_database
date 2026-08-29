import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_windows_message_box.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WindowsMessageBox implements IWindowsMessageBox {
  const WindowsMessageBox();

  @override
  void showWarning(String title, String message) {
    _showMessageBox(title, message, MB_OK | MB_ICONWARNING, 'warning');
  }

  @override
  void showInfo(String title, String message) {
    _showMessageBox(title, message, MB_OK | MB_ICONINFORMATION, 'info');
  }

  @override
  void showError(String title, String message) {
    _showMessageBox(title, message, MB_OK | MB_ICONERROR, 'error');
  }

  void _showMessageBox(
    String title,
    String message,
    MESSAGEBOX_STYLE flags,
    String type,
  ) {
    if (!Platform.isWindows) return;

    try {
      using((arena) {
        MessageBox(
          null,
          arena.pcwstr(message),
          arena.pcwstr(title),
          flags,
        );
      });
    } on Object catch (e) {
      LoggerService.debug('Windows MessageBox ($type): $e');
    }
  }
}
