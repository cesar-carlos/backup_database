import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/infrastructure/external/system/ipc/named_pipe_ffi.dart';
import 'package:backup_database/infrastructure/external/system/ipc/process_query_access.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'merges only limited query access and preserves existing process ACEs',
    () {
      final before = _processDacl();
      expect(ProcessQueryAccess.prepare(), isNull);
      final after = _processDacl();
      // A repeat must not accumulate duplicate ACEs.
      expect(ProcessQueryAccess.prepare(), isNull);
      expect(_processDacl(), after);
      final aces = RegExp(r'\([^)]*\)')
          .allMatches(after)
          .map((m) => m[0]!)
          .toList();
      expect(aces, contains('(A;;0x1000;;;AU)'));
      for (final old in RegExp(r'\([^)]*\)').allMatches(before)) {
        expect(aces, contains(old[0]));
      }
      expect(NamedPipeFfi.imagePathForPid(pid), isNotEmpty);
      expect(NamedPipeFfi.lastImageQueryFailure, isNull);
    },
    skip: !Platform.isWindows,
  );

  test(
    'native lookup reports operation and error then clears stale diagnostic',
    () {
      expect(NamedPipeFfi.imagePathForPid(0x7fffffff), isNull);
      expect(
        NamedPipeFfi.lastImageQueryFailure,
        matches(r'OpenProcess win32=\d+'),
      );
      expect(NamedPipeFfi.imagePathForPid(pid), isNotEmpty);
      expect(NamedPipeFfi.lastImageQueryFailure, isNull);
    },
    skip: !Platform.isWindows,
  );
}

String _processDacl() {
  final advapi = DynamicLibrary.open('advapi32.dll');
  final kernel = DynamicLibrary.open('kernel32.dll');
  final get = advapi
      .lookupFunction<
        Uint32 Function(
          IntPtr,
          Int32,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
        ),
        int Function(
          int,
          int,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
        )
      >('GetSecurityInfo');
  final convert = advapi
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Uint32,
          Uint32,
          Pointer<Pointer<Utf16>>,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Void>,
          int,
          int,
          Pointer<Pointer<Utf16>>,
          Pointer<Uint32>,
        )
      >('ConvertSecurityDescriptorToStringSecurityDescriptorW');
  final free = kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');
  final sd = calloc<Pointer<Void>>();
  final text = calloc<Pointer<Utf16>>();
  try {
    expect(get(-1, 6, 4, nullptr, nullptr, nullptr, nullptr, sd), 0);
    expect(convert(sd.value, 1, 4, text, nullptr), isNot(0));
    return text.value.toDartString();
  } finally {
    if (text.value != nullptr) free(text.value.cast());
    if (sd.value != nullptr) free(sd.value);
    calloc.free(text);
    calloc.free(sd);
  }
}
