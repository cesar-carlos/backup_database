import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:ffi/ffi.dart';

class WindowsUserService {
  static String? getCurrentUsername() {
    if (!Platform.isWindows) {
      return Platform.environment['USER'] ?? Platform.environment['USERNAME'];
    }

    try {
      final envUsername = Platform.environment['USERNAME'];
      if (envUsername != null && envUsername.isNotEmpty) {
        return envUsername;
      }

      final advapi32 = DynamicLibrary.open('advapi32.dll');

      final getUserNameW = advapi32
          .lookupFunction<
            Int32 Function(Pointer<Utf16>, Pointer<Uint32>),
            int Function(Pointer<Utf16>, Pointer<Uint32>)
          >('GetUserNameW');

      final bufferSize = calloc<Uint32>();
      bufferSize.value = 256;
      final buffer = calloc<Uint16>(256).cast<Utf16>();

      final result = getUserNameW(buffer, bufferSize);

      if (result != 0) {
        final username = buffer.toDartString();
        calloc.free(buffer.cast<Uint16>());
        calloc.free(bufferSize);
        return username;
      }

      calloc.free(buffer.cast<Uint16>());
      calloc.free(bufferSize);
      return null;
    } on Object catch (e) {
      LoggerService.warning(
        'Erro ao obter nome do usuário via Windows API: $e',
      );
      return Platform.environment['USERNAME'];
    }
  }
}
