import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const int _seeMaskNoCloseProcess = 0x40;
const int _infinite = 0xFFFFFFFF;

/// Win32 ERROR_CANCELLED — common when the user dismisses the UAC prompt.
const int kWin32ErrorCancelled = 1223;

class ShellExecuteRunAsResult {
  const ShellExecuteRunAsResult({
    required this.shellExecuteOk,
    this.win32LastError,
    this.processExitCode,
  });

  final bool shellExecuteOk;
  final int? win32LastError;
  final int? processExitCode;
}

String _quoteParametersArgument(String arg) {
  if (!arg.contains(' ') && !arg.contains('\t')) {
    return arg;
  }
  final escaped = arg.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

Future<ShellExecuteRunAsResult> shellExecuteRunAsAndWait({
  required String executablePath,
  required String parameters,
}) async {
  if (!Platform.isWindows) {
    return const ShellExecuteRunAsResult(shellExecuteOk: false);
  }

  final verb = 'runas'.toNativeUtf16();
  final file = executablePath.toNativeUtf16();
  final params = parameters.toNativeUtf16();
  final sei = calloc<SHELLEXECUTEINFO>();

  try {
    sei.ref
      ..cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..fMask = _seeMaskNoCloseProcess
      ..hwnd = 0
      ..lpVerb = verb
      ..lpFile = file
      ..lpParameters = params
      ..lpDirectory = nullptr
      ..nShow = SW_SHOWNORMAL
      ..hInstApp = 0
      ..lpIDList = nullptr
      ..lpClass = nullptr
      ..hkeyClass = 0
      ..dwHotKey = 0
      ..hIcon = 0
      ..hProcess = 0;

    final ok = ShellExecuteEx(sei);
    if (ok == 0) {
      return ShellExecuteRunAsResult(
        shellExecuteOk: false,
        win32LastError: GetLastError(),
      );
    }

    final hProcess = sei.ref.hProcess;
    if (hProcess == 0) {
      return const ShellExecuteRunAsResult(shellExecuteOk: true);
    }

    WaitForSingleObject(hProcess, _infinite);
    final exitPtr = calloc<Uint32>();
    try {
      GetExitCodeProcess(hProcess, exitPtr);
      return ShellExecuteRunAsResult(
        shellExecuteOk: true,
        processExitCode: exitPtr.value,
      );
    } finally {
      calloc.free(exitPtr);
      CloseHandle(hProcess);
    }
  } finally {
    calloc.free(sei);
    calloc.free(verb);
    calloc.free(file);
    calloc.free(params);
  }
}

String quotedLegacyScannerOutputArgument(String outputJsonPath) =>
    _quoteParametersArgument(outputJsonPath);
