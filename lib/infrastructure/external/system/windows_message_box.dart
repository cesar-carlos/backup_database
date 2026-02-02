import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_windows_message_box.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Implementation of [IWindowsMessageBox] using Win32 MessageBox API.
class WindowsMessageBox implements IWindowsMessageBox {
  const WindowsMessageBox();

  static const int _mbOk = 0x00000000;
  static const int _mbIconWarning = 0x00000030;
  static const int _mbIconInformation = 0x00000040;
  static const int _mbIconError = 0x00000010;

  @override
  void showWarning(String title, String message) {
    _showMessageBox(title, message, _mbOk | _mbIconWarning, 'warning');
  }

  @override
  void showInfo(String title, String message) {
    _showMessageBox(title, message, _mbOk | _mbIconInformation, 'info');
  }

  @override
  void showError(String title, String message) {
    _showMessageBox(title, message, _mbOk | _mbIconError, 'error');
  }

  void _showMessageBox(String title, String message, int flags, String type) {
    if (!Platform.isWindows) return;

    try {
      final titlePtr = title.toNativeUtf16();
      final messagePtr = message.toNativeUtf16();

      MessageBox(0, messagePtr, titlePtr, flags);

      calloc.free(messagePtr);
      calloc.free(titlePtr);
    } on Object catch (e) {
      LoggerService.debug('Windows MessageBox ($type): $e');
    }
  }
}
