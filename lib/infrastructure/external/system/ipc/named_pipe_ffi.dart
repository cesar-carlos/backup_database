import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/infrastructure/external/system/ipc/ipc_peer_guard.dart';
import 'package:backup_database/infrastructure/external/system/mutex_security_descriptor.dart';
import 'package:ffi/ffi.dart';

const int _genericRead = 0x80000000;
const int _genericWrite = 0x40000000;
const int _openExisting = 3;
const int _pipeAccessDuplex = 0x00000003;
const int _pipeRejectRemoteClients = 0x00000008;
const int _fileFlagFirstPipeInstance = 0x00080000;
const int _errorPipeBusy = 231;
const int _errorPipeConnected = 535;
const int _invalidHandleValue = -1;
const int _processQueryLimitedInformation = 0x1000;
const int _nmpwaitNoWait = 1;

class NamedPipeFfi {
  NamedPipeFfi._();

  static DynamicLibrary? _kernel32;

  static DynamicLibrary get _k32 {
    return _kernel32 ??= DynamicLibrary.open('kernel32.dll');
  }

  static final int Function(
    Pointer<Utf16>,
    int,
    int,
    int,
    int,
    int,
    int,
    Pointer<NativeType>,
  )
  _createNamedPipe = _k32
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
          Pointer<NativeType>,
        ),
        int Function(
          Pointer<Utf16>,
          int,
          int,
          int,
          int,
          int,
          int,
          Pointer<NativeType>,
        )
      >('CreateNamedPipeW');

  static final int Function(int, Pointer<NativeType>) _connectNamedPipe = _k32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<NativeType>),
        int Function(int, Pointer<NativeType>)
      >('ConnectNamedPipe');

  static final int Function(int) _disconnectNamedPipe = _k32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'DisconnectNamedPipe',
      );

  static final int Function(int, Pointer<NativeType>) _cancelIoEx = _k32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<NativeType>),
        int Function(int, Pointer<NativeType>)
      >('CancelIoEx');

  static final int Function(Pointer<Utf16>, int) _waitNamedPipe = _k32
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, int)
      >('WaitNamedPipeW');

  static final int Function(
    Pointer<Utf16>,
    int,
    int,
    Pointer<NativeType>,
    int,
    int,
    int,
  )
  _createFile = _k32
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<NativeType>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(
          Pointer<Utf16>,
          int,
          int,
          Pointer<NativeType>,
          int,
          int,
          int,
        )
      >('CreateFileW');

  static final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<NativeType>,
  )
  _readFile = _k32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<NativeType>,
        ),
        int Function(
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<NativeType>,
        )
      >('ReadFile');

  static final int Function(
    int,
    Pointer<Uint8>,
    int,
    Pointer<Uint32>,
    Pointer<NativeType>,
  )
  _writeFile = _k32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<NativeType>,
        ),
        int Function(
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<NativeType>,
        )
      >('WriteFile');

  static final int Function(int) _closeHandle = _k32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  static final int Function(int, Pointer<Uint32>) _getClientPid = _k32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetNamedPipeClientProcessId');

  static final int Function(int, Pointer<Uint32>) _getServerPid = _k32
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetNamedPipeServerProcessId');

  static final int Function() _getLastError = _k32
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

  static final int Function(int, int, int) _openProcess = _k32
      .lookupFunction<
        IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)
      >('OpenProcess');

  static final int Function(
    int,
    int,
    Pointer<Utf16>,
    Pointer<Uint32>,
  )
  _queryFullProcessImageName = _k32
      .lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>),
        int Function(int, int, Pointer<Utf16>, Pointer<Uint32>)
      >('QueryFullProcessImageNameW');

  static final int Function(Pointer<Utf16>, Pointer<Utf16>, int)
  _getLongPathName = _k32
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >('GetLongPathNameW');

  static final int Function(int) _flushFileBuffers = _k32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'FlushFileBuffers',
      );

  static bool handleIsValid(int handle) {
    return handle != 0 && handle != _invalidHandleValue;
  }

  static int _lastOperationError = 0;
  static int get lastError => _lastOperationError;

  static int createServerPipe({
    required String pipeName,
    required bool firstInstance,
    required MutexSecurityAttributes? security,
  }) {
    final namePtr = pipeName.toNativeUtf16();
    try {
      // Resolve GetLastError before the native operation: resolving an FFI
      // symbol (or freeing memory) can itself overwrite the thread error.
      _getLastError();
      var openMode = _pipeAccessDuplex;
      if (firstInstance) {
        openMode |= _fileFlagFirstPipeInstance;
      }
      const pipeMode = _pipeRejectRemoteClients;
      final handle = _createNamedPipe(
        namePtr,
        openMode,
        pipeMode,
        SingleInstanceConfig.ipcMaxPipeInstances,
        SingleInstanceConfig.ipcPipeBufferBytes,
        SingleInstanceConfig.ipcPipeBufferBytes,
        0,
        security?.pointer ?? nullptr,
      );
      _lastOperationError = handleIsValid(handle) ? 0 : _getLastError();
      return handle;
    } finally {
      calloc.free(namePtr);
    }
  }

  static bool connectServerPipe(int handle) {
    _getLastError();
    final ok = _connectNamedPipe(handle, nullptr);
    if (ok != 0) {
      return true;
    }
    return _getLastError() == _errorPipeConnected;
  }

  static void disconnect(int handle) {
    if (!handleIsValid(handle)) {
      return;
    }
    // A worker may be blocked in ReadFile. Disconnecting first can itself
    // block, preventing the server from reaching its shutdown deadline.
    _cancelIoEx(handle, nullptr);
    _disconnectNamedPipe(handle);
  }

  static void disconnectAndClose(int handle) {
    if (!handleIsValid(handle)) {
      return;
    }
    disconnect(handle);
    _closeHandle(handle);
  }

  static int? connectClient({
    required String pipeName,
    required Duration timeout,
  }) {
    final elapsed = Stopwatch()..start();
    var lastError = 2;
    while (elapsed.elapsed < timeout) {
      final remaining = timeout - elapsed.elapsed;
      final (handle, error) = _openClient(pipeName);
      if (handleIsValid(handle)) {
        return handle;
      }
      lastError = error;
      if (lastError != _errorPipeBusy) {
        // WaitNamedPipe returns immediately when no pipe exists. Retrying it
        // without a delay spins a CPU core for the entire connect timeout.
        if (lastError != 2) {
          throw FileSystemException(
            'CreateFileW named pipe',
            pipeName,
            OSError('Win32', lastError),
          );
        }
        sleep(Duration(milliseconds: remaining.inMilliseconds.clamp(1, 25)));
        continue;
      }
      final namePtr = pipeName.toNativeUtf16();
      try {
        final waited = _waitNamedPipe(
          namePtr,
          remaining.inMilliseconds.clamp(1, 0x7fffffff),
        );
        if (waited == 0) {
          lastError = _getLastError();
          if (lastError == 2) continue;
          throw FileSystemException(
            'WaitNamedPipeW',
            pipeName,
            OSError('Win32', lastError),
          );
        }
      } finally {
        calloc.free(namePtr);
      }
    }
    throw FileSystemException(
      'Named pipe unavailable before deadline',
      pipeName,
      OSError('Win32', lastError),
    );
  }

  static (int, int) _openClient(String pipeName) {
    final namePtr = pipeName.toNativeUtf16();
    try {
      _getLastError();
      final handle = _createFile(
        namePtr,
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        0,
        0,
      );
      final error = handleIsValid(handle) ? 0 : _getLastError();
      return (handle, error);
    } finally {
      calloc.free(namePtr);
    }
  }

  static void wakeServer(String pipeName) {
    final namePtr = pipeName.toNativeUtf16();
    try {
      _waitNamedPipe(namePtr, _nmpwaitNoWait);
      final handle = _createFile(
        namePtr,
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        0,
        0,
      );
      if (handleIsValid(handle)) {
        _closeHandle(handle);
      }
    } finally {
      calloc.free(namePtr);
    }
  }

  static String? readLine(int handle, {required int maxBytes}) {
    final chunk = calloc<Uint8>(256);
    final read = calloc<Uint32>();
    final builder = BytesBuilder(copy: false);
    try {
      while (true) {
        final ok = _readFile(handle, chunk, 256, read, nullptr);
        if (ok == 0 || read.value == 0) {
          return null;
        }
        for (var i = 0; i < read.value; i++) {
          final byte = chunk[i];
          if (byte == 10) {
            return utf8.decode(builder.takeBytes(), allowMalformed: true);
          }
          if (builder.length >= maxBytes) {
            return null;
          }
          builder.addByte(byte);
        }
      }
    } finally {
      calloc.free(chunk);
      calloc.free(read);
    }
  }

  static bool writeLine(int handle, String line) {
    final payload = Uint8List.fromList(utf8.encode('$line\n'));
    final ptr = calloc<Uint8>(payload.length);
    final written = calloc<Uint32>();
    try {
      ptr.asTypedList(payload.length).setAll(0, payload);
      final ok = _writeFile(
        handle,
        ptr,
        payload.length,
        written,
        nullptr,
      );
      if (ok == 0) {
        return false;
      }
      _flushFileBuffers(handle);
      return written.value == payload.length;
    } finally {
      calloc.free(ptr);
      calloc.free(written);
    }
  }

  static int? clientPid(int handle) {
    final pid = calloc<Uint32>();
    try {
      if (_getClientPid(handle, pid) == 0) {
        return null;
      }
      return pid.value;
    } finally {
      calloc.free(pid);
    }
  }

  static int? serverPid(int handle) {
    final pid = calloc<Uint32>();
    try {
      if (_getServerPid(handle, pid) == 0) {
        return null;
      }
      return pid.value;
    } finally {
      calloc.free(pid);
    }
  }

  static String? imagePathForPid(int pid) {
    if (!Platform.isWindows || pid <= 0) {
      return null;
    }
    final process = _openProcess(_processQueryLimitedInformation, 0, pid);
    if (!handleIsValid(process)) {
      return null;
    }
    const cap = 32768;
    final size = calloc<Uint32>();
    final buffer = calloc<Uint16>(cap).cast<Utf16>();
    size.value = cap;
    try {
      final ok = _queryFullProcessImageName(process, 0, buffer, size);
      if (ok == 0) {
        return null;
      }
      return buffer.toDartString();
    } finally {
      calloc.free(buffer.cast<Uint16>());
      calloc.free(size);
      _closeHandle(process);
    }
  }

  static const int _maxLongPathChars = 32768;

  static String? longPathName(String path) {
    if (!Platform.isWindows || path.isEmpty) {
      return null;
    }
    final direct = _readLongPath(path);
    if (direct != null) {
      return direct;
    }
    if (path.startsWith(r'\\?\')) {
      return null;
    }
    return _readLongPath(r'\\?\$path');
  }

  static String? _readLongPath(String path) {
    final input = path.toNativeUtf16();
    final buffer = calloc<Uint16>(_maxLongPathChars);
    try {
      final written = _getLongPathName(
        input,
        buffer.cast<Utf16>(),
        _maxLongPathChars,
      );
      if (written == 0 || written >= _maxLongPathChars) {
        return null;
      }
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(input);
      calloc.free(buffer);
    }
  }

  static IpcPeerGuard platformGuard({required String expectedImagePath}) {
    return IpcPeerGuard(
      expectedImagePath: () => expectedImagePath,
      resolveImagePath: imagePathForPid,
      expandLongPath: longPathName,
    );
  }
}
