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

  return using((arena) {
    final sei = arena<SHELLEXECUTEINFO>();
    sei.ref
      ..cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..fMask = _seeMaskNoCloseProcess
      ..hwnd = HWND(nullptr)
      ..lpVerb = PWSTR(arena.pcwstr('runas'))
      ..lpFile = PWSTR(arena.pcwstr(executablePath))
      ..lpParameters = PWSTR(arena.pcwstr(parameters))
      ..lpDirectory = PWSTR(nullptr)
      ..nShow = SW_SHOWNORMAL
      ..hInstApp = HINSTANCE(nullptr)
      ..lpIDList = nullptr
      ..lpClass = PWSTR(nullptr)
      ..hkeyClass = HKEY(nullptr)
      ..dwHotKey = 0
      ..hIcon = HANDLE(nullptr)
      ..hProcess = HANDLE(nullptr);

    final executed = ShellExecuteEx(sei);
    if (!executed.value) {
      return ShellExecuteRunAsResult(
        shellExecuteOk: false,
        win32LastError: executed.error,
      );
    }

    final hProcess = sei.ref.hProcess;
    if (!hProcess.isValid) {
      return const ShellExecuteRunAsResult(shellExecuteOk: true);
    }

    WaitForSingleObject(hProcess, _infinite);
    final exitPtr = arena<Uint32>();
    GetExitCodeProcess(hProcess, exitPtr);
    CloseHandle(hProcess);
    return ShellExecuteRunAsResult(
      shellExecuteOk: true,
      processExitCode: exitPtr.value,
    );
  });
}

String quotedLegacyScannerOutputArgument(String outputJsonPath) =>
    _quoteParametersArgument(outputJsonPath);
