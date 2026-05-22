import 'dart:io';

class WinrarInstallProbe {
  WinrarInstallProbe._();

  static const List<String> knownInstallPaths = [
    r'C:\Program Files\WinRAR\WinRAR.exe',
    r'C:\Program Files (x86)\WinRAR\WinRAR.exe',
  ];

  static Future<String?> findInstalledPath() async {
    for (final path in knownInstallPaths) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  static Future<bool> isInstalledInSystem() async =>
      (await findInstalledPath()) != null;
}
