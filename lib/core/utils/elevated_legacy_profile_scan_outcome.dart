import 'dart:convert';

import 'package:path/path.dart' as p;

const int kElevatedLegacyScanJsonSchemaVersion = 1;

enum LegacyElevatedScanMethod {
  nativeExecutable,
  powershell,
}

enum ElevatedLegacyScanFailureKind {
  notWindows,
  userDismissedUac,
  elevationLaunchFailed,
  elevatedProcessFailed,
  missingOutputFile,
  invalidJson,
  unexpectedError,
}

class ElevatedLegacyProfileScanOutcome {
  ElevatedLegacyProfileScanOutcome.success({
    required this.paths,
    required this.methodUsed,
    this.stderr = '',
  }) : userCancelledOrFailed = false,
       exitCode = 0,
       failureKind = null,
       win32LastError = null;

  ElevatedLegacyProfileScanOutcome.failed({
    required this.failureKind,
    this.paths = const <String>[],
    this.exitCode = 1,
    this.stderr = '',
    this.methodUsed,
    this.win32LastError,
  }) : userCancelledOrFailed = true;

  final List<String> paths;
  final bool userCancelledOrFailed;
  final int exitCode;
  final String stderr;
  final LegacyElevatedScanMethod? methodUsed;
  final ElevatedLegacyScanFailureKind? failureKind;
  final int? win32LastError;

  bool get userDismissedUac =>
      failureKind == ElevatedLegacyScanFailureKind.userDismissedUac;
}

ElevatedLegacyProfileScanOutcome decodeElevatedLegacyProfileScanJson(
  String raw,
  String stderr, {
  required LegacyElevatedScanMethod methodUsed,
}) {
  late final Map<String, dynamic> decoded;
  try {
    final dynamic parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      return ElevatedLegacyProfileScanOutcome.failed(
        failureKind: ElevatedLegacyScanFailureKind.invalidJson,
        stderr: stderr,
        methodUsed: methodUsed,
      );
    }
    decoded = parsed;
  } on Object {
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.invalidJson,
      stderr: stderr,
      methodUsed: methodUsed,
    );
  }

  final dynamic ver = decoded['schemaVersion'];
  if (ver != kElevatedLegacyScanJsonSchemaVersion) {
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.invalidJson,
      stderr: stderr,
      methodUsed: methodUsed,
    );
  }

  final dynamic list = decoded['paths'];
  if (list is! List<dynamic>) {
    return ElevatedLegacyProfileScanOutcome.failed(
      failureKind: ElevatedLegacyScanFailureKind.invalidJson,
      stderr: stderr,
      methodUsed: methodUsed,
    );
  }
  final paths = list.map((dynamic e) => p.normalize(e.toString())).toList()
    ..sort();

  return ElevatedLegacyProfileScanOutcome.success(
    paths: paths,
    methodUsed: methodUsed,
    stderr: stderr,
  );
}
