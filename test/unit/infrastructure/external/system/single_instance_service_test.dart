import 'dart:ffi';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc/in_memory_ipc_transport.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:backup_database/infrastructure/external/system/mutex_security_descriptor.dart';
import 'package:backup_database/infrastructure/external/system/single_instance_service.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:win32/win32.dart';

class _FailingIpc extends Mock implements IpcService {}

// Supply every native adapter, including APIs a scenario does not call.
// Resolving a production default may load kernel32 even before the first call.
SingleInstanceService createService({
  bool isDebugMode = true,
  int Function(Pointer<NativeType>, int, Pointer<Utf16>)? createMutex,
  int Function(int, int, Pointer<Utf16>)? openMutex,
  void Function(int)? setLastError,
  int Function()? getLastError,
  int Function(int)? closeHandle,
  bool Function()? isWindowsPlatform,
  SingleInstanceLockFallbackMode Function()? lockFallbackModeProvider,
  SecurityAttributesProvider? securityAttributesProvider,
  IpcService? ipcService,
  Future<bool> Function()? ipcServerProbe,
}) => SingleInstanceService.forTest(
  isDebugMode: isDebugMode,
  createMutex:
      createMutex ?? (_, _, _) => throw StateError('Unexpected CreateMutex'),
  openMutex: openMutex ?? (_, _, _) => throw StateError('Unexpected OpenMutex'),
  setLastError:
      setLastError ?? (_) => throw StateError('Unexpected SetLastError'),
  getLastError:
      getLastError ?? () => throw StateError('Unexpected GetLastError'),
  closeHandle: closeHandle ?? (_) => throw StateError('Unexpected CloseHandle'),
  isWindowsPlatform: isWindowsPlatform,
  lockFallbackModeProvider: lockFallbackModeProvider,
  securityAttributesProvider: securityAttributesProvider,
  ipcService: ipcService,
  ipcServerProbe: ipcServerProbe,
);

void main() {
  test(
    'service and session UIs coexist but a second executor cannot acquire',
    () async {
      final names = <String>{};
      final handles = <int, String>{};
      var nextHandle = 100;
      var lastError = 0;
      SingleInstanceService lock(String name) => SingleInstanceService.forTest(
        mutexName: name,
        isDebugMode: false,
        isWindowsPlatform: () => true,
        createMutex: (_, _, pointer) {
          final key = pointer.toDartString();
          lastError = names.add(key) ? 0 : ERROR_ALREADY_EXISTS;
          final handle = nextHandle++;
          if (lastError == 0) handles[handle] = key;
          return handle;
        },
        openMutex: (_, _, _) => 0,
        setLastError: (value) => lastError = value,
        getLastError: () => lastError,
        closeHandle: (handle) {
          names.remove(handles.remove(handle));
          return 1;
        },
        ipcService: IpcService(transport: InMemoryIpcTransport()),
      );
      final executor = lock(SingleInstanceConfig.instanceMutexName);
      final ui1 = lock(SingleInstanceConfig.administrativeMutex(1));
      final ui2 = lock(SingleInstanceConfig.administrativeMutex(2));
      final duplicate = lock(SingleInstanceConfig.instanceMutexName);
      final duplicateUi = lock(SingleInstanceConfig.administrativeMutex(1));
      expect(await executor.checkAndLock(isServiceMode: true), isTrue);
      expect(await ui1.checkAndLock(), isTrue);
      expect(await ui2.checkAndLock(), isTrue);
      expect(await duplicate.checkAndLock(), isFalse);
      expect(await duplicateUi.checkAndLock(), isFalse);
      await ui1.releaseLock();
      expect(names, contains(SingleInstanceConfig.instanceMutexName));
      final reopened = lock(SingleInstanceConfig.administrativeMutex(1));
      expect(await reopened.checkAndLock(), isTrue);
      await reopened.releaseLock();
      await ui2.releaseLock();
      await executor.releaseLock();
      expect(names, isEmpty);
    },
  );
  test(
    'IPC stop failure still closes mutex and permits reacquisition',
    () async {
      final ipc = _FailingIpc();
      when(ipc.stop).thenThrow(StateError('IPC stop failed'));
      var nextHandle = 100;
      final closed = <int>[];
      final service = createService(
        createMutex: (_, _, _) => nextHandle++,
        setLastError: (_) {},
        getLastError: () => 0,
        closeHandle: (handle) {
          closed.add(handle);
          return 1;
        },
        isWindowsPlatform: () => true,
        ipcService: ipc,
      );
      expect(await service.checkAndLock(), isTrue);
      await service.releaseLock();
      expect(closed, [100]);
      expect(service.isFirstInstance, isFalse);
      expect(await service.checkAndLock(), isTrue);
      await service.releaseLock();
      expect(closed, [100, 101]);
    },
  );
  group('SingleInstanceService.checkAndLock', () {
    for (final throws in [false, true]) {
      test(
        'release denies mutex failure despite explicit fail_open (throws=$throws)',
        () async {
          var probes = 0;
          final service = createService(
            isDebugMode: false,
            createMutex: (_, _, _) {
              if (throws) throw StateError('mutex unavailable');
              return 0;
            },
            setLastError: (_) {},
            getLastError: () => ERROR_ACCESS_DENIED,
            isWindowsPlatform: () => true,
            lockFallbackModeProvider: () =>
                SingleInstanceLockFallbackMode.failOpen,
            ipcServerProbe: () async {
              probes++;
              return false;
            },
          );
          expect(
            await service.checkAndLock(
              fallbackMode: SingleInstanceLockFallbackMode.failOpen,
            ),
            isFalse,
          );
          expect(
            service.lockDenialReason,
            SingleInstanceLockDenialReason.creationFailed,
          );
          expect(probes, 0);
        },
      );
    }
    test(
      'should return false when mutex creation fails and fallback is fail_safe',
      () async {
        final service = createService(
          createMutex: (_, _, _) => 0,
          setLastError: (_) {},
          getLastError: () => 5,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failSafe,
        );

        final result = await service.checkAndLock();

        expect(result, isFalse);
        expect(service.isFirstInstance, isFalse);
        expect(
          service.lockDenialReason,
          SingleInstanceLockDenialReason.creationFailed,
        );
      },
    );

    test(
      'should return true when mutex creation fails and fallback is fail_open',
      () async {
        final service = createService(
          createMutex: (_, _, _) => 0,
          setLastError: (_) {},
          getLastError: () => 5,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failOpen,
        );

        final result = await service.checkAndLock();

        expect(result, isTrue);
        expect(service.isFirstInstance, isTrue);
      },
    );

    test(
      'should return false and close handle when mutex already exists',
      () async {
        var closeHandleCallCount = 0;
        final service = createService(
          createMutex: (_, _, _) => 123,
          setLastError: (_) {},
          getLastError: () => ERROR_ALREADY_EXISTS,
          closeHandle: (_) {
            closeHandleCallCount++;
            return 1;
          },
          isWindowsPlatform: () => true,
        );

        final result = await service.checkAndLock();

        expect(result, isFalse);
        expect(service.isFirstInstance, isFalse);
        expect(closeHandleCallCount, equals(1));
        expect(
          service.lockDenialReason,
          SingleInstanceLockDenialReason.alreadyRunning,
        );
      },
    );

    test(
      'should return false on exception when fallback is fail_safe',
      () async {
        final service = createService(
          createMutex: (_, _, _) => throw StateError('mutex_error'),
          setLastError: (_) {},
          getLastError: () => 0,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failSafe,
        );

        final result = await service.checkAndLock();

        expect(result, isFalse);
        expect(service.isFirstInstance, isFalse);
        expect(
          service.lockDenialReason,
          SingleInstanceLockDenialReason.creationFailed,
        );
      },
    );

    test(
      'should return true on exception when fallback is fail_open',
      () async {
        final service = createService(
          createMutex: (_, _, _) => throw StateError('mutex_error'),
          setLastError: (_) {},
          getLastError: () => 0,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failOpen,
        );

        final result = await service.checkAndLock();

        expect(result, isTrue);
        expect(service.isFirstInstance, isTrue);
        expect(service.lockDenialReason, isNull);
      },
    );

    test(
      'should return false when service mode and CreateMutex fails even if '
      'provider is fail_open',
      () async {
        final service = createService(
          createMutex: (_, _, _) => 0,
          setLastError: (_) {},
          getLastError: () => 5,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failOpen,
        );

        final result = await service.checkAndLock(isServiceMode: true);

        expect(result, isFalse);
        expect(service.isFirstInstance, isFalse);
        expect(
          service.lockDenialReason,
          SingleInstanceLockDenialReason.creationFailed,
        );
      },
    );

    test(
      'should return false on exception in service mode even if provider is '
      'fail_open',
      () async {
        final service = createService(
          createMutex: (_, _, _) => throw StateError('mutex_error'),
          setLastError: (_) {},
          getLastError: () => 0,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failOpen,
        );

        final result = await service.checkAndLock(isServiceMode: true);

        expect(result, isFalse);
        expect(service.isFirstInstance, isFalse);
      },
    );

    // F1 — passes the SECURITY_ATTRIBUTES pointer provided by the
    // `securityAttributesProvider` into CreateMutexW (vs nullptr).
    test(
      'should pass security attributes pointer to CreateMutexW when '
      'provider returns a non-null descriptor',
      () async {
        Pointer<NativeType>? capturedAttrs;
        var disposeCallCount = 0;
        final attrsBytes = calloc<Uint8>(4);
        final dummyAttrs = MutexSecurityAttributesTestFactory.create(
          pointer: attrsBytes.cast(),
          dispose: () {
            disposeCallCount++;
            calloc.free(attrsBytes);
          },
        );

        final service = createService(
          createMutex: (attrs, _, _) {
            capturedAttrs = attrs;
            return 0;
          },
          setLastError: (_) {},
          getLastError: () => 0,
          isWindowsPlatform: () => true,
          securityAttributesProvider: () => dummyAttrs,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failSafe,
        );

        await service.checkAndLock();

        expect(capturedAttrs, isNotNull);
        expect(capturedAttrs!.address, equals(attrsBytes.address));
        expect(disposeCallCount, equals(1));
      },
    );

    test(
      'should fall back to nullptr SECURITY_ATTRIBUTES when provider '
      'returns null',
      () async {
        Pointer<NativeType>? capturedAttrs;
        final service = createService(
          createMutex: (attrs, _, _) {
            capturedAttrs = attrs;
            return 123;
          },
          setLastError: (_) {},
          getLastError: () => 0,
          isWindowsPlatform: () => true,
          securityAttributesProvider: () => null,
        );

        await service.checkAndLock();

        expect(capturedAttrs, equals(nullptr));
      },
    );

    // F2 — fail_open + active IPC owner detected → must deny.
    test(
      'should deny startup in fail_open when active IPC server is detected '
      'after mutex creation fails',
      () async {
        final service = createService(
          createMutex: (_, _, _) => 0,
          setLastError: (_) {},
          getLastError: () => ERROR_ACCESS_DENIED,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failOpen,
          ipcServerProbe: () async => true,
        );

        final result = await service.checkAndLock();

        expect(result, isFalse);
        expect(service.isFirstInstance, isFalse);
        expect(
          service.lockDenialReason,
          SingleInstanceLockDenialReason.alreadyRunning,
        );
      },
    );

    test(
      'should deny startup in fail_open when active IPC server is detected '
      'after exception',
      () async {
        final service = createService(
          createMutex: (_, _, _) => throw StateError('mutex_error'),
          setLastError: (_) {},
          getLastError: () => 0,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failOpen,
          ipcServerProbe: () async => true,
        );

        final result = await service.checkAndLock();

        expect(result, isFalse);
        expect(service.isFirstInstance, isFalse);
        expect(
          service.lockDenialReason,
          SingleInstanceLockDenialReason.alreadyRunning,
        );
      },
    );

    test(
      'should swallow IPC probe failure in fail_open path and still allow '
      'startup when no owner is detected',
      () async {
        final service = createService(
          createMutex: (_, _, _) => 0,
          setLastError: (_) {},
          getLastError: () => ERROR_ACCESS_DENIED,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failOpen,
          ipcServerProbe: () async => throw StateError('probe boom'),
        );

        final result = await service.checkAndLock();

        expect(result, isTrue);
        expect(service.isFirstInstance, isTrue);
      },
    );

    // F3 — guard idempotente: 2ª chamada não pode sobrescrever handle nem
    // inverter o estado.
    test(
      'should be idempotent across multiple checkAndLock calls and not '
      'leak handles',
      () async {
        var createMutexCallCount = 0;
        var closeHandleCallCount = 0;

        final service = createService(
          createMutex: (_, _, _) {
            createMutexCallCount++;
            return 999;
          },
          setLastError: (_) {},
          getLastError: () => 0,
          closeHandle: (_) {
            closeHandleCallCount++;
            return 1;
          },
          isWindowsPlatform: () => true,
        );

        final first = await service.checkAndLock();
        final second = await service.checkAndLock();
        final third = await service.checkAndLock();

        expect(first, isTrue);
        expect(second, isTrue);
        expect(third, isTrue);
        expect(createMutexCallCount, equals(1));
        expect(closeHandleCallCount, equals(0));
        expect(service.isFirstInstance, isTrue);
      },
    );

    test(
      'should remain denied across multiple checkAndLock calls when first '
      'attempt detected ERROR_ALREADY_EXISTS',
      () async {
        var createMutexCallCount = 0;
        var closeHandleCallCount = 0;

        final service = createService(
          createMutex: (_, _, _) {
            createMutexCallCount++;
            return 555;
          },
          setLastError: (_) {},
          getLastError: () => ERROR_ALREADY_EXISTS,
          closeHandle: (_) {
            closeHandleCallCount++;
            return 1;
          },
          isWindowsPlatform: () => true,
        );

        final first = await service.checkAndLock();
        final second = await service.checkAndLock();

        expect(first, isFalse);
        expect(second, isFalse);
        // Apenas a primeira chamada deve interagir com CreateMutex/CloseHandle.
        expect(createMutexCallCount, equals(1));
        expect(closeHandleCallCount, equals(1));
      },
    );
  });

  group('SingleInstanceService.isInstanceMutexHeld', () {
    test('should return false when OpenMutex reports the mutex is missing', () {
      final service = createService(
        openMutex: (_, _, _) => 0,
        setLastError: (_) {},
        getLastError: () => ERROR_FILE_NOT_FOUND,
        isWindowsPlatform: () => true,
      );

      expect(service.isInstanceMutexHeld(), isFalse);
    });

    test('should return true and close the handle when the mutex exists', () {
      var closeCount = 0;
      final service = createService(
        openMutex: (_, _, _) => 42,
        setLastError: (_) {},
        getLastError: () => 0,
        closeHandle: (_) {
          closeCount++;
          return 1;
        },
        isWindowsPlatform: () => true,
      );

      expect(service.isInstanceMutexHeld(), isTrue);
      expect(closeCount, 1);
    });

    test('should keep retrying when OpenMutex fails for another reason', () {
      final service = createService(
        openMutex: (_, _, _) => 0,
        setLastError: (_) {},
        getLastError: () => ERROR_ACCESS_DENIED,
        isWindowsPlatform: () => true,
      );

      expect(service.isInstanceMutexHeld(), isTrue);
    });
  });
}

/// Test-only factory para construir [MutexSecurityAttributes] sem depender
/// da API real do Win32 (`advapi32!ConvertStringSecurityDescriptor...`).
/// Permite validar que o ponteiro retornado pelo provider chega até
/// `CreateMutexW` E que `dispose` é chamado pelo serviço.
class MutexSecurityAttributesTestFactory {
  MutexSecurityAttributesTestFactory._();

  static MutexSecurityAttributes create({
    required Pointer<NativeType> pointer,
    required void Function() dispose,
  }) {
    return _StubMutexSecurityAttributes(pointer: pointer, onDispose: dispose);
  }
}

class _StubMutexSecurityAttributes implements MutexSecurityAttributes {
  _StubMutexSecurityAttributes({
    required this.pointer,
    required this._onDispose,
  });

  @override
  final Pointer<NativeType> pointer;

  final void Function() _onDispose;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose();
  }
}
