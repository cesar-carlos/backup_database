import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../../core/utils/logger_service.dart';
import 'ipc_service.dart';

// Definir a função CreateMutex do Windows
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createMutex = _kernel32.lookupFunction<
    IntPtr Function(Pointer, Int32, Pointer<Utf16>),
    int Function(Pointer, int, Pointer<Utf16>)>('CreateMutexW');

class SingleInstanceService {
  static final SingleInstanceService _instance = SingleInstanceService._();
  factory SingleInstanceService() => _instance;
  SingleInstanceService._();

  static const String _mutexName = 'Global\\BackupDatabaseMutex_{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}';
  
  int _mutexHandle = 0;
  bool _isFirstInstance = false;
  final IpcService _ipcService = IpcService();

  /// Verifica se é a primeira instância do aplicativo usando Named Mutex do Windows
  /// Retorna true se é a primeira instância, false caso contrário
  Future<bool> checkAndLock() async {
    try {
      if (!Platform.isWindows) {
        LoggerService.warning('Single instance check não suportado nesta plataforma');
        _isFirstInstance = true;
        return true;
      }

      // Criar ou abrir mutex nomeado
      final mutexNamePtr = _mutexName.toNativeUtf16();
      
      // CreateMutex retorna handle para o mutex
      // Se o mutex já existir, GetLastError retornará ERROR_ALREADY_EXISTS
      _mutexHandle = _createMutex(nullptr, 0, mutexNamePtr);
      
      final lastError = GetLastError();
      
      calloc.free(mutexNamePtr);

      if (_mutexHandle == 0) {
        LoggerService.error('Erro ao criar mutex: código $lastError');
        // Em caso de erro, permitir execução
        _isFirstInstance = true;
        return true;
      }

      // ERROR_ALREADY_EXISTS = 183
      if (lastError == ERROR_ALREADY_EXISTS) {
        LoggerService.info('Outra instância já está em execução (Mutex existe)');
        _isFirstInstance = false;
        
        // Fechar o handle do mutex
        CloseHandle(_mutexHandle);
        _mutexHandle = 0;
        
        return false;
      }

      LoggerService.info('Primeira instância do aplicativo (Mutex criado)');
      _isFirstInstance = true;
      return true;
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar instância única', e, stackTrace);
      // Em caso de erro, permitir execução
      _isFirstInstance = true;
      return true;
    }
  }

  /// Inicia o servidor IPC para receber comandos de outras instâncias
  Future<bool> startIpcServer({Function()? onShowWindow}) async {
    try {
      return await _ipcService.startServer(onShowWindow: onShowWindow);
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao iniciar IPC Server', e, stackTrace);
      return false;
    }
  }

  /// Envia comando para a instância existente mostrar a janela
  static Future<bool> notifyExistingInstance() async {
    return await IpcService.sendShowWindow();
  }

  /// Libera o mutex e para o servidor IPC
  Future<void> releaseLock() async {
    try {
      // Parar servidor IPC
      await _ipcService.stop();
      
      // Liberar mutex
      if (_mutexHandle != 0) {
        CloseHandle(_mutexHandle);
        _mutexHandle = 0;
        LoggerService.debug('Mutex liberado');
      }
    } catch (e) {
      LoggerService.warning('Erro ao liberar lock: $e');
    }
  }

  bool get isFirstInstance => _isFirstInstance;
  bool get isIpcRunning => _ipcService.isRunning;
}

