import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:path/path.dart' as p;

class TempDirectoryService {
  TempDirectoryService({required IMachineSettingsRepository machineSettings})
    : _machineSettings = machineSettings;

  static const String _downloadsSubdir = r'BackupDatabase\Downloads';

  final IMachineSettingsRepository _machineSettings;

  Directory? _downloadsDirCache;

  Future<Directory> getTempDirectory() async {
    final customPath = await _machineSettings.getCustomTempDownloadsPath();
    if (customPath != null && customPath.isNotEmpty) {
      final customDir = Directory(customPath);
      if (await _isValidDirectory(customDir)) {
        LoggerService.info('Usando pasta temp customizada: $customPath');
        return customDir;
      }
      LoggerService.warning(
        'Pasta temp customizada inválida ou sem permissão: $customPath',
      );
      await clearCustomTempPath();
    }

    final systemTemp = Directory.systemTemp;
    LoggerService.info('Usando pasta temp do sistema: ${systemTemp.path}');
    return systemTemp;
  }

  Future<Directory> getDownloadsDirectory() async {
    if (_downloadsDirCache != null) {
      return _downloadsDirCache!;
    }

    final baseTemp = await getTempDirectory();
    final downloadsPath = p.join(baseTemp.path, _downloadsSubdir);
    final downloadsDir = Directory(downloadsPath);

    if (!await downloadsDir.exists()) {
      try {
        await downloadsDir.create(recursive: true);
        LoggerService.info('Pasta de downloads criada: $downloadsPath');
      } on Object catch (e, stackTrace) {
        LoggerService.error(
          'Falha ao criar pasta de downloads: $e',
          e,
          stackTrace,
        );
        rethrow;
      }
    }

    _downloadsDirCache = downloadsDir;
    return downloadsDir;
  }

  Future<bool> setCustomTempPath(String path) async {
    final dir = Directory(path);

    if (!await _isValidDirectory(dir)) {
      LoggerService.warning('Tentativa de definir path inválido: $path');
      return false;
    }

    await _machineSettings.setCustomTempDownloadsPath(path);
    _downloadsDirCache = null;

    LoggerService.info('Pasta temp customizada definida: $path');
    return true;
  }

  Future<String?> getCustomTempPath() async =>
      _machineSettings.getCustomTempDownloadsPath();

  Future<void> clearCustomTempPath() async {
    await _machineSettings.setCustomTempDownloadsPath(null);
    _downloadsDirCache = null;
    LoggerService.info(
      'Pasta temp customizada removida. Usando temp do sistema.',
    );
  }

  Future<bool> _isValidDirectory(Directory dir) async {
    try {
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } on Object catch (e) {
          LoggerService.warning('Não foi possível criar diretório: $e');
          return false;
        }
      }

      final testFile = File(
        p.join(
          dir.path,
          '.write_test_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      await testFile.writeAsString('test');
      await testFile.delete();

      return true;
    } on Object catch (e, stackTrace) {
      LoggerService.warning(
        'Diretório sem permissão de escrita: ${dir.path}',
        e,
        stackTrace,
      );
      return false;
    }
  }

  void clearCache() {
    _downloadsDirCache = null;
  }

  Future<bool> validateDownloadsDirectory() async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      final isValid = await _isValidDirectory(downloadsDir);

      if (!isValid) {
        LoggerService.error(
          'Pasta de downloads sem permissão de escrita: ${downloadsDir.path}',
        );
      }

      return isValid;
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao validar pasta de downloads: $e',
        e,
        stackTrace,
      );
      return false;
    }
  }
}
