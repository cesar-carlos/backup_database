import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const int _cryptProtectLocalMachine = 0x4;

Uint8List protectWithDpapiLocalMachine(Uint8List plain) {
  if (!Platform.isWindows) {
    throw StateError('DPAPI machine scope is only supported on Windows');
  }

  final inputLen = plain.length;
  final pInput = calloc<Uint8>(inputLen);
  pInput.asTypedList(inputLen).setRange(0, inputLen, plain);

  final dataIn = calloc<CRYPT_INTEGER_BLOB>();
  dataIn.ref
    ..cbData = inputLen
    ..pbData = pInput;

  final dataOut = calloc<CRYPT_INTEGER_BLOB>();

  try {
    final ok = CryptProtectData(
      dataIn,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      _cryptProtectLocalMachine,
      dataOut,
    );
    if (ok == 0) {
      final err = GetLastError();
      throw WindowsException(err);
    }

    final outLen = dataOut.ref.cbData;
    final outPtr = dataOut.ref.pbData;
    final cipher = Uint8List.fromList(outPtr.asTypedList(outLen));
    LocalFree(outPtr);
    return cipher;
  } finally {
    calloc.free(pInput);
    calloc.free(dataIn);
    calloc.free(dataOut);
  }
}

Uint8List unprotectWithDpapiLocalMachine(Uint8List cipher) {
  if (!Platform.isWindows) {
    throw StateError('DPAPI machine scope is only supported on Windows');
  }

  final inputLen = cipher.length;
  final pInput = calloc<Uint8>(inputLen);
  pInput.asTypedList(inputLen).setRange(0, inputLen, cipher);

  final dataIn = calloc<CRYPT_INTEGER_BLOB>();
  dataIn.ref
    ..cbData = inputLen
    ..pbData = pInput;

  final dataOut = calloc<CRYPT_INTEGER_BLOB>();

  try {
    final ok = CryptUnprotectData(
      dataIn,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      _cryptProtectLocalMachine,
      dataOut,
    );
    if (ok == 0) {
      final err = GetLastError();
      throw WindowsException(err);
    }

    final outLen = dataOut.ref.cbData;
    final outPtr = dataOut.ref.pbData;
    final plain = Uint8List.fromList(outPtr.asTypedList(outLen));
    LocalFree(outPtr);
    return plain;
  } finally {
    calloc.free(pInput);
    calloc.free(dataIn);
    calloc.free(dataOut);
  }
}
