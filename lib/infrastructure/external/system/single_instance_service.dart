import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final int Function(Pointer<NativeType>, int, Pointer<Utf16>) _createMutex =
    _kernel32.lookupFunction<
      IntPtr Function(Pointer, Int32, Pointer<Utf16>),
      int Function(Pointer, int, Pointer<Utf16>)
    >('CreateMutexW');

/// Implementation of [ISingleInstanceService] for Windows.
///
/// Uses Windows mutexes to ensure only one instance runs at a time,
/// and IPC to communicate between instances.
class SingleInstanceService implements ISingleInstanceService {
  factory SingleInstanceService() => _instance;
  SingleInstanceService._();
  static final SingleInstanceService _instance = SingleInstanceService._();

  int _mutexHandle = 0;
  bool _isFirstInstance = false;
  final IpcService _ipcService = IpcService();

  @override
  Future<bool> checkAndLock({bool isServiceMode = false}) async {
    try {
      if (!Platform.isWindows) {
        LoggerService.warning(
          'Single instance check não suportado nesta plataforma',
        );
        _isFirstInstance = true;
        return true;
      }

      final mutexName = isServiceMode
          ? SingleInstanceConfig.serviceMutexName
          : SingleInstanceConfig.uiMutexName;
      final modeName = isServiceMode ? 'Serviço' : 'UI';
      final mutexNamePtr = mutexName.toNativeUtf16();

      SetLastError(0);

      _mutexHandle = _createMutex(nullptr, 0, mutexNamePtr);

      final lastError = GetLastError();

      calloc.free(mutexNamePtr);

      if (_mutexHandle == 0 || _mutexHandle == -1) {
        LoggerService.error(
          'Erro ao criar mutex: handle=$_mutexHandle, código=$lastError',
        );
        _isFirstInstance = true;
        return true;
      }

      if (lastError == ERROR_ALREADY_EXISTS) {
        LoggerService.info(
          'Outra instância de $modeName já está em execução (Mutex existe)',
        );
        _isFirstInstance = false;

        CloseHandle(_mutexHandle);
        _mutexHandle = 0;

        return false;
      }

      LoggerService.info(
        'Primeira instância de $modeName do aplicativo (Mutex criado) - Handle: $_mutexHandle',
      );
      _isFirstInstance = true;
      return true;
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar instância única', e, stackTrace);
      _isFirstInstance = true;
      return true;
    }
  }

  @override
  Future<bool> startIpcServer({Function()? onShowWindow}) async {
    try {
      return await _ipcService.startServer(onShowWindow: onShowWindow);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao iniciar IPC Server', e, stackTrace);
      return false;
    }
  }

  /// Notifies an existing instance to show its window.
  static Future<bool> notifyExistingInstance() async {
    return IpcService.sendShowWindow();
  }

  @override
  Future<void> releaseLock() async {
    try {
      await _ipcService.stop();

      if (_mutexHandle != 0) {
        CloseHandle(_mutexHandle);
        _mutexHandle = 0;
        LoggerService.debug('Mutex liberado');
      }
    } on Object catch (e) {
      LoggerService.warning('Erro ao liberar lock: $e');
    }
  }

  @override
  bool get isFirstInstance => _isFirstInstance;

  @override
  bool get isIpcRunning => _ipcService.isRunning;
}
