import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WindowsMessageBox {
  static const int _mbOk = 0x00000000;
  static const int _mbIconWarning = 0x00000030;
  static const int _mbIconInformation = 0x00000040;
  static const int _mbIconError = 0x00000010;

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
    } catch (_) {
    }
  }

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
    } catch (_) {
    }
  }

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
    } catch (_) {
    }
  }
}
