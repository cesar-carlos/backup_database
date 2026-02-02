import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Utility class for showing native Windows message boxes.
///
/// Uses the Win32 MessageBox API directly for displaying system-level
/// notifications that work even without a Flutter UI context.
class WindowsMessageBox {
  WindowsMessageBox._();

  static const int _mbOk = 0x00000000;
  static const int _mbIconWarning = 0x00000030;
  static const int _mbIconInformation = 0x00000040;
  static const int _mbIconError = 0x00000010;

  /// Shows a warning message box.
  static void showWarning(String title, String message) {
    if (!Platform.isWindows) return;

    try {
      final titlePtr = title.toNativeUtf16();
      final messagePtr = message.toNativeUtf16();

      MessageBox(
        0,
        messagePtr,
        titlePtr,
        _mbOk | _mbIconWarning,
      );

      calloc.free(messagePtr);
      calloc.free(titlePtr);
    } on Object catch (e) {
      LoggerService.debug('Windows MessageBox (warning): $e');
    }
  }

  /// Shows an informational message box.
  static void showInfo(String title, String message) {
    if (!Platform.isWindows) return;

    try {
      final titlePtr = title.toNativeUtf16();
      final messagePtr = message.toNativeUtf16();

      MessageBox(
        0,
        messagePtr,
        titlePtr,
        _mbOk | _mbIconInformation,
      );

      calloc.free(messagePtr);
      calloc.free(titlePtr);
    } on Object catch (e) {
      LoggerService.debug('Windows MessageBox (info): $e');
    }
  }

  /// Shows an error message box.
  static void showError(String title, String message) {
    if (!Platform.isWindows) return;

    try {
      final titlePtr = title.toNativeUtf16();
      final messagePtr = message.toNativeUtf16();

      MessageBox(
        0,
        messagePtr,
        titlePtr,
        _mbOk | _mbIconError,
      );

      calloc.free(messagePtr);
      calloc.free(titlePtr);
    } on Object catch (e) {
      LoggerService.debug('Windows MessageBox (error): $e');
    }
  }
}
