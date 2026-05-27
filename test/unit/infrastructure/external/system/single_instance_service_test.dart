import 'dart:ffi';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/infrastructure/external/system/mutex_security_descriptor.dart';
import 'package:backup_database/infrastructure/external/system/single_instance_service.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  group('SingleInstanceService.checkAndLock', () {
    test(
      'should return false when mutex creation fails and fallback is fail_safe',
      () async {
        final service = SingleInstanceService.forTest(
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
      },
    );

    test(
      'should return true when mutex creation fails and fallback is fail_open',
      () async {
        final service = SingleInstanceService.forTest(
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
        final service = SingleInstanceService.forTest(
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
      },
    );

    test(
      'should return false on exception when fallback is fail_safe',
      () async {
        final service = SingleInstanceService.forTest(
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
      },
    );

    test(
      'should return true on exception when fallback is fail_open',
      () async {
        final service = SingleInstanceService.forTest(
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
      },
    );

    test(
      'should return false when service mode and CreateMutex fails even if '
      'provider is fail_open',
      () async {
        final service = SingleInstanceService.forTest(
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
      },
    );

    test(
      'should return false on exception in service mode even if provider is '
      'fail_open',
      () async {
        final service = SingleInstanceService.forTest(
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

        final service = SingleInstanceService.forTest(
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
        final service = SingleInstanceService.forTest(
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
        final service = SingleInstanceService.forTest(
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
      },
    );

    test(
      'should deny startup in fail_open when active IPC server is detected '
      'after exception',
      () async {
        final service = SingleInstanceService.forTest(
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
      },
    );

    test(
      'should swallow IPC probe failure in fail_open path and still allow '
      'startup when no owner is detected',
      () async {
        final service = SingleInstanceService.forTest(
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

        final service = SingleInstanceService.forTest(
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

        final service = SingleInstanceService.forTest(
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
    required void Function() onDispose,
  }) : _onDispose = onDispose;

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
