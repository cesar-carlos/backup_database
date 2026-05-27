import 'dart:ffi';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:backup_database/infrastructure/external/system/mutex_security_descriptor.dart';
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

typedef SecurityAttributesProvider = MutexSecurityAttributes? Function();

/// Implementation of [ISingleInstanceService] for Windows.
///
/// Uses Windows mutexes to ensure only one instance runs at a time,
/// and IPC to communicate between instances.
class SingleInstanceService implements ISingleInstanceService {
  factory SingleInstanceService() => _instance;
  SingleInstanceService._({
    int Function(Pointer<NativeType>, int, Pointer<Utf16>)? createMutex,
    void Function(int)? setLastError,
    int Function()? getLastError,
    int Function(int)? closeHandle,
    bool Function()? isWindowsPlatform,
    SingleInstanceLockFallbackMode Function()? lockFallbackModeProvider,
    SecurityAttributesProvider? securityAttributesProvider,
    IpcService? ipcService,
    Future<bool> Function()? ipcServerProbe,
  }) : _createMutexFn = createMutex ?? _createMutex,
       _setLastErrorFn = setLastError ?? SetLastError,
       _getLastErrorFn = getLastError ?? GetLastError,
       _closeHandleFn = closeHandle ?? CloseHandle,
       _isWindowsPlatformFn = isWindowsPlatform ?? (() => Platform.isWindows),
       _lockFallbackModeProvider =
           lockFallbackModeProvider ?? _defaultLockFallbackModeProvider,
       _securityAttributesProvider =
           securityAttributesProvider ??
           MutexSecurityDescriptor.buildEveryoneAccess,
       _ipcService = ipcService ?? IpcService(),
       _ipcServerProbe = ipcServerProbe ?? IpcService.checkServerRunning;
  static final SingleInstanceService _instance = SingleInstanceService._();

  SingleInstanceService.forTest({
    int Function(Pointer<NativeType>, int, Pointer<Utf16>)? createMutex,
    void Function(int)? setLastError,
    int Function()? getLastError,
    int Function(int)? closeHandle,
    bool Function()? isWindowsPlatform,
    SingleInstanceLockFallbackMode Function()? lockFallbackModeProvider,
    SecurityAttributesProvider? securityAttributesProvider,
    IpcService? ipcService,
    Future<bool> Function()? ipcServerProbe,
  }) : this._(
         createMutex: createMutex,
         setLastError: setLastError,
         getLastError: getLastError,
         closeHandle: closeHandle,
         isWindowsPlatform: isWindowsPlatform,
         lockFallbackModeProvider: lockFallbackModeProvider,
         securityAttributesProvider: securityAttributesProvider ?? (() => null),
         ipcService: ipcService,
         // Default seguro para testes: sem dono externo. Tests podem
         // sobrescrever para `() async => true` ao validar F2 (probe
         // defensivo no fail_open) ou exercer o caminho de denial.
         ipcServerProbe: ipcServerProbe ?? (() async => false),
       );

  int _mutexHandle = 0;
  bool _isFirstInstance = false;
  bool _checkAndLockCompleted = false;
  final int Function(Pointer<NativeType>, int, Pointer<Utf16>) _createMutexFn;
  final void Function(int) _setLastErrorFn;
  final int Function() _getLastErrorFn;
  final int Function(int) _closeHandleFn;
  final bool Function() _isWindowsPlatformFn;
  final SingleInstanceLockFallbackMode Function() _lockFallbackModeProvider;
  final SecurityAttributesProvider _securityAttributesProvider;
  final IpcService _ipcService;
  final Future<bool> Function() _ipcServerProbe;

  @override
  Future<bool> checkAndLock({bool isServiceMode = false}) async {
    // F3: guard idempotente. Sem isso, uma 2ª chamada sobrescreveria
    // `_mutexHandle` (vazando o handle anterior) e inverteria
    // `_isFirstInstance` baseando-se em `ERROR_ALREADY_EXISTS` do próprio
    // processo.
    if (_checkAndLockCompleted) {
      LoggerService.warning(
        'event=single_instance_check_and_lock_reentrant '
        'isFirstInstance=$_isFirstInstance handle=$_mutexHandle',
      );
      return _isFirstInstance;
    }

    final modeName = isServiceMode ? 'service' : 'ui';

    try {
      if (!_isWindowsPlatformFn()) {
        LoggerService.warning(
          'Single instance check não suportado nesta plataforma',
        );
        _isFirstInstance = true;
        _checkAndLockCompleted = true;
        return true;
      }

      final lockResult = _tryCreateNamedMutex();
      final mutexHandle = lockResult.handle;
      final lastError = lockResult.lastError;
      _mutexHandle = mutexHandle;

      if (mutexHandle == 0 || mutexHandle == -1) {
        return _handleMutexCreationFailure(
          modeName: modeName,
          lastError: lastError,
          isServiceMode: isServiceMode,
        );
      }

      if (lastError == ERROR_ALREADY_EXISTS) {
        LoggerService.infoWithContext(
          'event=single_instance_lock_denied ownerRole=$modeName',
        );
        _isFirstInstance = false;
        _checkAndLockCompleted = true;

        _closeHandleFn(_mutexHandle);
        _mutexHandle = 0;

        return false;
      }

      LoggerService.infoWithContext(
        'event=single_instance_lock_acquired ownerRole=$modeName '
        'handle=$_mutexHandle',
      );
      _isFirstInstance = true;
      _checkAndLockCompleted = true;
      return true;
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar instância única', e, stackTrace);
      final fallbackMode = isServiceMode
          ? SingleInstanceLockFallbackMode.failSafe
          : _lockFallbackModeProvider();
      if (fallbackMode == SingleInstanceLockFallbackMode.failSafe) {
        LoggerService.error(
          '[SingleInstance] Fallback mode fail_safe: refusing startup after '
          'exception to preserve exclusivity.',
        );
        _isFirstInstance = false;
        _checkAndLockCompleted = true;
        return false;
      }
      // F2: mesmo no path fail_open, antes de declarar "sou o primeiro"
      // após uma exceção, faz probe defensivo no IPC. Se houver outro
      // dono respondendo PONG v1 válido, NÃO permite a 2ª instância.
      final hasActiveIpc = await _probeActiveIpcSafely();
      if (hasActiveIpc) {
        LoggerService.error(
          'event=single_instance_fail_open_blocked_by_active_ipc '
          'ownerRole=$modeName reason=exception action=deny',
        );
        _isFirstInstance = false;
        _checkAndLockCompleted = true;
        return false;
      }
      _isFirstInstance = true;
      _checkAndLockCompleted = true;
      return true;
    }
  }

  _LockResult _tryCreateNamedMutex() {
    const mutexName = SingleInstanceConfig.instanceMutexName;
    final mutexNamePtr = mutexName.toNativeUtf16();
    // F1: passa SECURITY_ATTRIBUTES com DACL Everyone (MUTEX_ALL_ACCESS).
    // Sem isso, o serviço como LocalSystem cria o mutex com DACL default
    // (SYSTEM/Admin only), e a UI do usuário comum recebe
    // ERROR_ACCESS_DENIED ao tentar abrir o mesmo nome — anulando o
    // enforcement de instância única na maioria das instalações reais.
    final securityAttrs = _securityAttributesProvider();
    final securityAttrsPtr = securityAttrs?.pointer ?? nullptr;

    _setLastErrorFn(0);

    final handle = _createMutexFn(securityAttrsPtr, 0, mutexNamePtr);
    final lastError = _getLastErrorFn();

    calloc.free(mutexNamePtr);
    securityAttrs?.dispose();

    return _LockResult(handle: handle, lastError: lastError);
  }

  Future<bool> _handleMutexCreationFailure({
    required String modeName,
    required int lastError,
    required bool isServiceMode,
  }) async {
    final fallbackMode = isServiceMode
        ? SingleInstanceLockFallbackMode.failSafe
        : _lockFallbackModeProvider();

    // F1 (log): diferencia ACL denied de outros erros para facilitar
    // triagem no campo. ERROR_ACCESS_DENIED (5) tipicamente significa que
    // o mutex existe MAS foi criado por outro principal com DACL
    // restritivo — o app pode subir igual via fallback de IPC.
    final lockEventName = lastError == ERROR_ACCESS_DENIED
        ? 'single_instance_lock_acl_denied'
        : 'single_instance_lock_error';

    if (fallbackMode == SingleInstanceLockFallbackMode.failSafe) {
      LoggerService.error(
        'event=$lockEventName ownerRole=$modeName '
        'handle=$_mutexHandle getLastError=$lastError '
        'fallback=fail_safe action=deny',
      );
      _isFirstInstance = false;
      _checkAndLockCompleted = true;
      return false;
    }

    // F2: probe defensivo antes de declarar "sou o primeiro" no
    // fail_open. Evita 2 instâncias reais quando a falha do mutex
    // mascara o fato de já existir outro dono respondendo no IPC.
    final hasActiveIpc = await _probeActiveIpcSafely();
    if (hasActiveIpc) {
      LoggerService.error(
        'event=single_instance_fail_open_blocked_by_active_ipc '
        'ownerRole=$modeName getLastError=$lastError action=deny',
      );
      _isFirstInstance = false;
      _checkAndLockCompleted = true;
      return false;
    }

    LoggerService.warning(
      'event=$lockEventName ownerRole=$modeName '
      'handle=$_mutexHandle getLastError=$lastError '
      'fallback=fail_open action=allow',
    );
    _isFirstInstance = true;
    _checkAndLockCompleted = true;
    return true;
  }

  Future<bool> _probeActiveIpcSafely() async {
    try {
      return await _ipcServerProbe();
    } on Object catch (e, s) {
      LoggerService.warning(
        'event=single_instance_ipc_probe_failed reason=$e',
        e,
        s,
      );
      return false;
    }
  }

  @override
  Future<bool> startIpcServer({
    required String role,
    Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  }) async {
    try {
      return await _ipcService.startServer(
        role: role,
        onShowWindow: onShowWindow,
        onRunSchedule: onRunSchedule,
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao iniciar IPC Server', e, stackTrace);
      return false;
    }
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
      _checkAndLockCompleted = false;
      _isFirstInstance = false;
    } on Object catch (e) {
      LoggerService.warning('Erro ao liberar lock: $e');
    }
  }

  @override
  bool get isFirstInstance => _isFirstInstance;

  @override
  bool get isIpcRunning => _ipcService.isRunning;
}

class _LockResult {
  const _LockResult({required this.handle, required this.lastError});
  final int handle;
  final int lastError;
}
