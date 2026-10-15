import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:ffi/ffi.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;
import 'package:win32/win32.dart';

const int _scManagerConnect = 0x0001;
const int _serviceChangeConfig = 0x0002;
const int _serviceNoChange = 0xFFFFFFFF;
const int _unknownWin32Error = 1;

typedef ServiceAccountChange = int Function({
  required String serviceName,
  required String serviceUser,
  required String servicePassword,
});

final int Function(
  Pointer,
  int,
  int,
  int,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Uint32>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
)
_changeServiceConfigW = DynamicLibrary.open('advapi32.dll')
    .lookupFunction<
      Int32 Function(
        Pointer,
        Uint32,
        Uint32,
        Uint32,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
      ),
      int Function(
        Pointer,
        int,
        int,
        int,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Pointer<Utf16>,
      )
    >('ChangeServiceConfigW');

int changeServiceAccountWithWin32({
  required String serviceName,
  required String serviceUser,
  required String servicePassword,
}) {
  if (!Platform.isWindows) {
    return _unknownWin32Error;
  }
  final scm = OpenSCManager(null, null, _scManagerConnect);
  if (!scm.value.isValid) {
    return _nonZero(scm.error.code);
  }
  final opened = using((arena) {
    return OpenService(
      scm.value,
      arena.pcwstr(serviceName),
      _serviceChangeConfig,
    );
  });
  if (!opened.value.isValid) {
    scm.value.close();
    return _nonZero(opened.error.code);
  }
  try {
    final changed = using((arena) {
      final noText = nullptr.cast<Utf16>();
      return _changeServiceConfigW(
        opened.value,
        _serviceNoChange,
        _serviceNoChange,
        _serviceNoChange,
        noText,
        noText,
        nullptr.cast<Uint32>(),
        noText,
        arena.pcwstr(serviceUser),
        arena.pcwstr(servicePassword),
        noText,
      );
    });
    if (changed != 0) {
      return 0;
    }
    return _nonZero(GetLastError().code);
  } finally {
    opened.value.close();
    scm.value.close();
  }
}

int _nonZero(int code) => code == 0 ? _unknownWin32Error : code;

class WindowsServiceAccountConfig {
  WindowsServiceAccountConfig({ServiceAccountChange? changeAccount})
    : changeAccount = changeAccount ?? changeServiceAccountWithWin32;

  final ServiceAccountChange changeAccount;

  Future<rd.Result<void>> setLogonAccount({
    required String serviceName,
    required String serviceUser,
    required String servicePassword,
  }) async {
    final code = changeAccount(
      serviceName: serviceName,
      serviceUser: serviceUser,
      servicePassword: servicePassword,
    );
    if (code != 0) {
      return rd.Failure(
        ServerFailure(
          message:
              'Falha ao definir a conta do serviço '
              '(ChangeServiceConfig, erro $code).',
        ),
      );
    }
    return const rd.Success(unit);
  }
}
