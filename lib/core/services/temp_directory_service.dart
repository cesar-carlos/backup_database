import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class TempDirectoryService {
  static const String _customTempPathKey = 'custom_temp_downloads_path';
  static const String _downloadsSubdir = r'BackupDatabase\Downloads';

  SharedPreferences? _prefsCache;
  Directory? _downloadsDirCache;

  /// Obtém a pasta temporária base para downloads.
  /// Ordem de prioridade:
  /// 1. Custom path configurado pelo usuário (se válido)
  /// 2. Temp do sistema (Directory.systemTemp)
  Future<Directory> getTempDirectory() async {
    final customPath = await getCustomTempPath();
    if (customPath != null) {
      final customDir = Directory(customPath);
      if (await _isValidDirectory(customDir)) {
        LoggerService.info('Usando pasta temp customizada: $customPath');
        return customDir;
      }
      LoggerService.warning(
        'Pasta temp customizada inválida ou sem permissão: $customPath',
      );
      // Invalida cache e fallback para temp do sistema
      await clearCustomTempPath();
    }

    // Fallback: temp do sistema
    final systemTemp = Directory.systemTemp;
    LoggerService.info('Usando pasta temp do sistema: ${systemTemp.path}');
    return systemTemp;
  }

  /// Obtém a pasta específica para downloads de backups do servidor.
  /// Cria a pasta se não existir.
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

  /// Define um caminho customizado para a pasta temporária.
  /// Valida se o path é válido e tem permissão de escrita antes de salvar.
  Future<bool> setCustomTempPath(String path) async {
    final dir = Directory(path);

    if (!await _isValidDirectory(dir)) {
      LoggerService.warning('Tentativa de definir path inválido: $path');
      return false;
    }

    final prefs = await _getPrefs();
    await prefs.setString(_customTempPathKey, path);
    _prefsCache = prefs;

    // Limpa cache para forçar revalidação no próximo acesso
    _downloadsDirCache = null;

    LoggerService.info('Pasta temp customizada definida: $path');
    return true;
  }

  /// Obtém o caminho customizado configurado pelo usuário (se existir).
  Future<String?> getCustomTempPath() async {
    final prefs = await _getPrefs();
    return prefs.getString(_customTempPathKey);
  }

  /// Remove o caminho customizado e volta a usar temp do sistema.
  Future<void> clearCustomTempPath() async {
    final prefs = await _getPrefs();
    await prefs.remove(_customTempPathKey);
    _prefsCache = prefs;
    _downloadsDirCache = null;
    LoggerService.info(
      'Pasta temp customizada removida. Usando temp do sistema.',
    );
  }

  /// Valida se o diretório existe e tem permissão de escrita.
  Future<bool> _isValidDirectory(Directory dir) async {
    try {
      // Verifica se existe
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } on Object catch (e) {
          LoggerService.warning('Não foi possível criar diretório: $e');
          return false;
        }
      }

      // Verifica permissão de escrita criando arquivo de teste
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

  Future<SharedPreferences> _getPrefs() async {
    if (_prefsCache != null) {
      return _prefsCache!;
    }
    final prefs = await SharedPreferences.getInstance();
    _prefsCache = prefs;
    return prefs;
  }

  /// Limpa o cache de diretórios. Use após mudar a configuração.
  void clearCache() {
    _downloadsDirCache = null;
  }

  /// Valida se a pasta de downloads tem permissão de escrita.
  /// Retorna true se a pasta é válida, false caso contrário.
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
