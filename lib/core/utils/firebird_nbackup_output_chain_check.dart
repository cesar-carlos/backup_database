import 'dart:io';

import 'package:path/path.dart' as p;

Future<String?> missingFirebirdNbackupChainPattern({
  required String outputDirectory,
  required String databaseStem,
  required int nbackupLevel,
}) async {
  if (nbackupLevel < 1) {
    return null;
  }
  final dir = Directory(outputDirectory);
  if (!await dir.exists()) {
    return 'pasta de saida inexistente ou inacessivel';
  }
  final basenames = <String>[];
  await for (final FileSystemEntity entity in dir.list(
    followLinks: false,
  )) {
    if (entity is File) {
      basenames.add(p.basename(entity.path));
    }
  }

  bool hasMatch(String prefix) {
    const suffix = '.nbk';
    for (final name in basenames) {
      if (name.length < prefix.length + suffix.length) {
        continue;
      }
      if (!name.startsWith(prefix)) {
        continue;
      }
      if (!name.toLowerCase().endsWith(suffix)) {
        continue;
      }
      return true;
    }
    return false;
  }

  final fullPrefix = '${databaseStem}_full_';
  if (!hasMatch(fullPrefix)) {
    return '"$fullPrefix*.nbk"';
  }
  for (var level = 1; level < nbackupLevel; level++) {
    final incPrefix = '${databaseStem}_nbackup_B${level}_';
    if (!hasMatch(incPrefix)) {
      return '"$incPrefix*.nbk"';
    }
  }
  return null;
}
