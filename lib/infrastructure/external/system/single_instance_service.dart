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

SingleInstanceLockFallbackMode _defaultLockFallbackModeProvider() =>
    SingleInstanceConfig.lockFallbackMode;

/// Implementation of [ISingleInstanceService] for Windows.
///
/// Uses Windows mutexes to ensure only one instance runs at a time,
/// and IPC to communicate between instances.
class SingleInstanceService implements ISingleInstanceService {
  factory SingleInstanceService() => _instance;
  SingleInstanceService._({
    int Function(Pointer<NativeType>, int, Pointer<Utf16>)? createMutex,
    int Function()? getLastError,
    int Function(int)? closeHandle,
    bool Function()? isWindowsPlatform,
    SingleInstanceLockFallbackMode Function()? lockFallbackModeProvider,
    IpcService? ipcService,
  }) : _createMutexFn = createMutex ?? _createMutex,
       _getLastErrorFn = getLastError ?? GetLastError,
       _closeHandleFn = closeHandle ?? CloseHandle,
       _isWindowsPlatformFn = isWindowsPlatform ?? (() => Platform.isWindows),
       _lockFallbackModeProvider =
           lockFallbackModeProvider ?? _defaultLockFallbackModeProvider,
       _ipcService = ipcService ?? IpcService();
  static final SingleInstanceService _instance = SingleInstanceService._();

  SingleInstanceService.forTest({
    int Function(Pointer<NativeType>, int, Pointer<Utf16>)? createMutex,
    int Function()? getLastError,
    int Function(int)? closeHandle,
    bool Function()? isWindowsPlatform,
    SingleInstanceLockFallbackMode Function()? lockFallbackModeProvider,
    IpcService? ipcService,
  }) : this._(
         createMutex: createMutex,
         getLastError: getLastError,
         closeHandle: closeHandle,
         isWindowsPlatform: isWindowsPlatform,
         lockFallbackModeProvider: lockFallbackModeProvider,
         ipcService: ipcService,
       );

  int _mutexHandle = 0;
  bool _isFirstInstance = false;
  final int Function(Pointer<NativeType>, int, Pointer<Utf16>) _createMutexFn;
  final int Function() _getLastErrorFn;
  final int Function(int) _closeHandleFn;
  final bool Function() _isWindowsPlatformFn;
  final SingleInstanceLockFallbackMode Function() _lockFallbackModeProvider;
  final IpcService _ipcService;

  @override
  Future<bool> checkAndLock({bool isServiceMode = false}) async {
    try {
      if (!_isWindowsPlatformFn()) {
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

      _mutexHandle = _createMutexFn(nullptr, 0, mutexNamePtr);

      final lastError = _getLastErrorFn();

      calloc.free(mutexNamePtr);

      if (_mutexHandle == 0 || _mutexHandle == -1) {
        final fallbackMode = _lockFallbackModeProvider();
        if (fallbackMode == SingleInstanceLockFallbackMode.failSafe) {
          LoggerService.error(
            '[SingleInstance] CreateMutex failed: handle=$_mutexHandle, '
            'GetLastError=$lastError. '
            'Fallback mode fail_safe: refusing startup to preserve exclusivity.',
          );
          _isFirstInstance = false;
          return false;
        }

        LoggerService.warning(
          '[SingleInstance] CreateMutex failed: handle=$_mutexHandle, '
          'GetLastError=$lastError. '
          'Fallback mode fail_open: proceeding without exclusivity guarantee.',
        );
        _isFirstInstance = true;
        return true;
      }

      if (lastError == ERROR_ALREADY_EXISTS) {
        LoggerService.info(
          'Outra instância de $modeName já está em execução (Mutex existe)',
        );
        _isFirstInstance = false;

        _closeHandleFn(_mutexHandle);
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
        _closeHandleFn(_mutexHandle);
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
