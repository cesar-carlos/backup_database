import 'dart:io';

import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _defaultProgramData = r'C:\ProgramData';

Future<Directory> resolveMachineRootDirectory() async {
  if (Platform.isWindows) {
    final programData =
        Platform.environment['ProgramData'] ?? _defaultProgramData;
    return Directory(p.join(programData, 'BackupDatabase'));
  }

  return getApplicationDocumentsDirectory();
}

Future<Directory> resolveMachineDataDirectory() async {
  if (Platform.isWindows) {
    final root = await resolveMachineRootDirectory();
    return Directory(p.join(root.path, MachineStorageLayout.data));
  }

  return getApplicationDocumentsDirectory();
}

Future<Directory> resolveMachineStagingBackupsDirectory() async {
  final root = await resolveMachineRootDirectory();
  if (Platform.isWindows) {
    return Directory(
      p.join(
        root.path,
        MachineStorageLayout.staging,
        MachineStorageLayout.stagingBackups,
      ),
    );
  }
  return Directory(p.join(root.path, 'backups'));
}

Future<Directory> resolveMachineLocksDirectory() async {
  final root = await resolveMachineRootDirectory();
  return Directory(p.join(root.path, MachineStorageLayout.locks));
}

Future<Directory> resolveMachineSecretsDirectory() async {
  final root = await resolveMachineRootDirectory();
  return Directory(p.join(root.path, MachineStorageLayout.secrets));
}

Future<Directory?> resolveLegacyWindowsUserAppDataDirectory() async {
  if (!Platform.isWindows) {
    return null;
  }
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) {
    return null;
  }
  return Directory(p.join(appData, 'Backup Database'));
}

Future<Directory> resolveAppDataDirectory() => resolveMachineRootDirectory();
