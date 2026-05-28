import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' show LocalFree;

/// SDDL string que concede `MUTEX_ALL_ACCESS` (0x1F0001) ao grupo
/// `WD` (Everyone / S-1-1-0).
///
/// Motivação: o mutex `Global\BackupDatabase_InstanceMutex_{GUID}` precisa
/// ser visível para QUALQUER processo do app na máquina — UI rodando como
/// usuário comum E serviço rodando como `LocalSystem` precisam conseguir
/// abrir/criar o mesmo nome e detectar `ERROR_ALREADY_EXISTS`.
///
/// Sem este DACL explícito, `CreateMutexW(nullptr, ...)` usa o DACL default
/// do token criador. Se o serviço cria primeiro como SYSTEM, a UI do
/// usuário não-admin recebe `ERROR_ACCESS_DENIED (5)` ao tentar abrir o
/// mesmo nome — e o enforcement de instância única falha silenciosamente
/// (ou em `fail_open`, gera 2 instâncias reais).
const String _mutexAllAccessForEveryoneSddl = 'D:(A;;0x1F0001;;;WD)';

const int _sddlRevision1 = 1;

/// Layout do struct Win32 `SECURITY_ATTRIBUTES`:
/// ```c
/// typedef struct _SECURITY_ATTRIBUTES {
///   DWORD  nLength;
///   LPVOID lpSecurityDescriptor;
///   BOOL   bInheritHandle;
/// } SECURITY_ATTRIBUTES;
/// ```
final class SecurityAttributesStruct extends Struct {
  @Uint32()
  external int nLength;

  external Pointer<NativeType> lpSecurityDescriptor;

  @Int32()
  external int bInheritHandle;
}

/// Resultado de [MutexSecurityDescriptor.buildEveryoneAccess]: contém o
/// ponteiro para `SECURITY_ATTRIBUTES` pronto para passar a `CreateMutexW`
/// + um [dispose] que libera o `SECURITY_DESCRIPTOR` (via `LocalFree`) e
/// o próprio `SECURITY_ATTRIBUTES` (via `calloc.free`).
class MutexSecurityAttributes {
  MutexSecurityAttributes._({
    required this.pointer,
    required void Function() dispose,
  }) : _dispose = dispose;

  /// Ponteiro pronto para ser passado como `lpMutexAttributes` em
  /// `CreateMutexW`. Pode ser `nullptr` se a construção falhar (caller
  /// deve cair em `nullptr` = DACL default).
  final Pointer<NativeType> pointer;

  final void Function() _dispose;

  bool _disposed = false;

  /// Libera recursos. Idempotente.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dispose();
  }
}

/// Helper para construir `SECURITY_ATTRIBUTES` permissivo para mutex
/// machine-global compartilhado entre processos rodando como contas
/// diferentes (típico: UI = usuário; Service = LocalSystem).
class MutexSecurityDescriptor {
  MutexSecurityDescriptor._();

  /// Constrói um `SECURITY_ATTRIBUTES` com DACL que permite
  /// `MUTEX_ALL_ACCESS` para Everyone.
  ///
  /// Retorna `null` se a construção falhar (ex.: API indisponível). O
  /// caller deve então cair no comportamento legado (`nullptr` = DACL
  /// default do token criador).
  static MutexSecurityAttributes? buildEveryoneAccess() {
    if (!Platform.isWindows) return null;

    DynamicLibrary advapi32;
    try {
      advapi32 = DynamicLibrary.open('advapi32.dll');
    } on Object {
      return null;
    }

    final convertFn = advapi32
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16> stringSecurityDescriptor,
            Uint32 stringSDRevision,
            Pointer<Pointer<NativeType>> securityDescriptor,
            Pointer<Uint32> securityDescriptorSize,
          ),
          int Function(
            Pointer<Utf16> stringSecurityDescriptor,
            int stringSDRevision,
            Pointer<Pointer<NativeType>> securityDescriptor,
            Pointer<Uint32> securityDescriptorSize,
          )
        >('ConvertStringSecurityDescriptorToSecurityDescriptorW');

    final sddlPtr = _mutexAllAccessForEveryoneSddl.toNativeUtf16();
    final outSdPtr = calloc<Pointer<NativeType>>();
    final outSizePtr = calloc<Uint32>();

    try {
      final ok = convertFn(sddlPtr, _sddlRevision1, outSdPtr, outSizePtr);
      if (ok == 0) {
        return null;
      }

      final sdPtr = outSdPtr.value;
      final attrs = calloc<SecurityAttributesStruct>();
      attrs.ref
        ..nLength = sizeOf<SecurityAttributesStruct>()
        ..lpSecurityDescriptor = sdPtr
        ..bInheritHandle = 0;

      return MutexSecurityAttributes._(
        pointer: attrs.cast(),
        dispose: () {
          LocalFree(sdPtr);
          calloc.free(attrs);
        },
      );
    } finally {
      calloc.free(sddlPtr);
      calloc.free(outSdPtr);
      calloc.free(outSizePtr);
    }
  }
}
