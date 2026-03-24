import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

Future<bool> hasMachineBootstrapFlag({
  required String fileName,
  String? legacySecureStorageKey,
  FlutterSecureStorage? legacyStorage,
  Directory? machineRootOverride,
}) async {
  final marker = await _machineBootstrapFlagFile(
    fileName: fileName,
    machineRootOverride: machineRootOverride,
  );
  if (await marker.exists()) {
    return true;
  }

  if (legacySecureStorageKey == null) {
    return false;
  }

  final storage = legacyStorage ?? const FlutterSecureStorage();
  try {
    final legacyValue = await storage.read(key: legacySecureStorageKey);
    if (legacyValue != 'true') {
      return false;
    }
    await markMachineBootstrapFlag(
      fileName: fileName,
      legacySecureStorageKey: legacySecureStorageKey,
      legacyStorage: storage,
      machineRootOverride: machineRootOverride,
    );
    return true;
  } on Exception catch (e) {
    LoggerService.warning(
      'Erro ao migrar flag legada "$legacySecureStorageKey" para machine-scope: $e',
    );
    return false;
  }
}

Future<void> markMachineBootstrapFlag({
  required String fileName,
  String? legacySecureStorageKey,
  FlutterSecureStorage? legacyStorage,
  Directory? machineRootOverride,
}) async {
  final marker = await _machineBootstrapFlagFile(
    fileName: fileName,
    machineRootOverride: machineRootOverride,
  );
  await marker.parent.create(recursive: true);

  final tempFile = File('${marker.path}.tmp');
  await tempFile.writeAsString(
    'completed_at_utc=${DateTime.now().toUtc().toIso8601String()}\n',
    flush: true,
  );
  if (await marker.exists()) {
    await marker.delete();
  }
  await tempFile.rename(marker.path);

  if (legacySecureStorageKey != null) {
    final storage = legacyStorage ?? const FlutterSecureStorage();
    try {
      await storage.delete(key: legacySecureStorageKey);
    } on Exception catch (e) {
      LoggerService.warning(
        'Erro ao remover flag legada "$legacySecureStorageKey": $e',
      );
    }
  }
}

Future<File> _machineBootstrapFlagFile({
  required String fileName,
  Directory? machineRootOverride,
}) async {
  final machineRoot =
      machineRootOverride ?? await resolveMachineRootDirectory();
  return File(
    p.join(machineRoot.path, MachineStorageLayout.config, fileName),
  );
}
