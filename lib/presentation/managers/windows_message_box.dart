import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Helper para mostrar MessageBox nativa do Windows
class WindowsMessageBox {
  static const int _mbOk = 0x00000000;
  static const int _mbIconWarning = 0x00000030;
  static const int _mbIconInformation = 0x00000040;
  static const int _mbIconError = 0x00000010;

  /// Mostra uma MessageBox de aviso ao usuário
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
    } catch (e) {
      // Silenciar erro em caso de falha na MessageBox
    }
  }

  /// Mostra uma MessageBox de informação ao usuário
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
    } catch (e) {
      // Silenciar erro em caso de falha na MessageBox
    }
  }

  /// Mostra uma MessageBox de erro ao usuário
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
    } catch (e) {
      // Silenciar erro em caso de falha na MessageBox
    }
  }
}
