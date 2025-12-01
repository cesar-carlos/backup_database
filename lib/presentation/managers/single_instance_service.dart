import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger_service.dart';

class SingleInstanceService {
  static final SingleInstanceService _instance = SingleInstanceService._();
  factory SingleInstanceService() => _instance;
  SingleInstanceService._();

  static const String _lockFileName = '.backup_database.lock';
  File? _lockFile;
  bool _isFirstInstance = false;

  /// Verifica se é a primeira instância do aplicativo
  /// Retorna true se é a primeira instância, false caso contrário
  /// 
  /// Usa uma abordagem mais permissiva que não bloqueia processos filhos como webviews
  Future<bool> checkAndLock() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      _lockFile = File('${appDir.path}/$_lockFileName');

      if (await _lockFile!.exists()) {
        // Verificar idade do lock file
        try {
          final stat = await _lockFile!.stat();
          final lockAge = DateTime.now().difference(stat.modified);
          
          // Se o lock é muito antigo (> 1 minuto), assumir que o processo morreu
          if (lockAge.inSeconds > 60) {
            await _lockFile!.delete();
            LoggerService.debug('Lock file antigo removido (idade: ${lockAge.inSeconds}s)');
          } else {
            // Lock recente, verificar se processo ainda existe
            final processName = Platform.resolvedExecutable.split(Platform.pathSeparator).last;
            final processResult = await Process.run(
              'tasklist',
              ['/FI', 'IMAGENAME eq $processName', '/FO', 'CSV', '/NH'],
              runInShell: true,
            );

            // Se encontrou processos, verificar se são instâncias diferentes
            if (processResult.exitCode == 0) {
              final output = processResult.stdout.toString();
              final processCount = output.split('\n').where((line) => 
                line.trim().isNotEmpty && line.contains(processName)
              ).length;
              
              // Se há mais de um processo, pode ser webview ou outra instância
              // Por segurança, apenas bloquear se o lock é muito recente (< 5 segundos)
              if (lockAge.inSeconds < 5 && processCount > 1) {
                LoggerService.info('Outra instância pode estar em execução');
                _isFirstInstance = false;
                return false;
              }
            }
          }
        } catch (e) {
          // Se houver erro, remover lock e continuar
          LoggerService.debug('Erro ao verificar lock: $e');
          try {
            await _lockFile!.delete();
          } catch (_) {
            // Ignorar erro ao deletar
          }
        }
      }

      // Criar ou atualizar arquivo lock
      await _lockFile!.writeAsString(DateTime.now().toIso8601String());
      _isFirstInstance = true;

      LoggerService.info('Primeira instância do aplicativo');
      return true;
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar instância única', e, stackTrace);
      // Em caso de erro, permitir execução
      _isFirstInstance = true;
      return true;
    }
  }

  Future<void> releaseLock() async {
    try {
      if (_lockFile != null && await _lockFile!.exists()) {
        await _lockFile!.delete();
        LoggerService.debug('Lock file removido');
      }
    } catch (e) {
      LoggerService.warning('Erro ao remover lock file: $e');
    }
  }

  bool get isFirstInstance => _isFirstInstance;
}

