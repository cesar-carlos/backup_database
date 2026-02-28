import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String _defaultProgramData = r'C:\ProgramData';

Future<Directory> resolveAppDataDirectory() async {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory(p.join(appData, 'Backup Database'));
    }

    final programData =
        Platform.environment['ProgramData'] ?? _defaultProgramData;
    return Directory(p.join(programData, 'BackupDatabase'));
  }

  return getApplicationDocumentsDirectory();
}
