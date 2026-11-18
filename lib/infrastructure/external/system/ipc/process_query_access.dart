import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class _Trustee extends Struct {
  external Pointer<Void> multipleTrustee;
  @Int32()
  external int multipleOperation;
  @Int32()
  external int form;
  @Int32()
  external int type;
  external Pointer<Void> name;
}

final class _ExplicitAccess extends Struct {
  @Uint32()
  external int permissions;
  @Int32()
  external int mode;
  @Uint32()
  external int inheritance;
  external _Trustee trustee;
}

/// Allows authenticated Windows accounts to verify this process's image.
/// Merges a limited-query ACE into the existing DACL, never replacing it
/// with a permissive/null DACL. Does not grant memory, terminate or write access.
class ProcessQueryAccess {
  ProcessQueryAccess._();

  static String? prepare() {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final advapi = DynamicLibrary.open('advapi32.dll');
    final current = kernel.lookupFunction<IntPtr Function(), int Function()>(
      'GetCurrentProcess',
    );
    final free = kernel
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('LocalFree');
    final getSecurity = advapi
        .lookupFunction<
          Uint32 Function(
            IntPtr,
            Int32,
            Uint32,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
          ),
          int Function(
            int,
            int,
            int,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
          )
        >('GetSecurityInfo');
    final setSecurity = advapi
        .lookupFunction<
          Uint32 Function(
            IntPtr,
            Int32,
            Uint32,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
          ),
          int Function(
            int,
            int,
            int,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
          )
        >('SetSecurityInfo');
    final convertSid = advapi
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>),
          int Function(Pointer<Utf16>, Pointer<Pointer<Void>>)
        >('ConvertStringSidToSidW');
    final merge = advapi
        .lookupFunction<
          Uint32 Function(
            Uint32,
            Pointer<_ExplicitAccess>,
            Pointer<Void>,
            Pointer<Pointer<Void>>,
          ),
          int Function(
            int,
            Pointer<_ExplicitAccess>,
            Pointer<Void>,
            Pointer<Pointer<Void>>,
          )
        >('SetEntriesInAclW');
    final lastError = kernel.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
    );
    final sd = calloc<Pointer<Void>>();
    final oldAcl = calloc<Pointer<Void>>();
    final newAcl = calloc<Pointer<Void>>();
    final sid = calloc<Pointer<Void>>();
    final sidText = 'S-1-5-11'.toNativeUtf16();
    final entry = calloc<_ExplicitAccess>();
    try {
      // SE_KERNEL_OBJECT = 6, DACL_SECURITY_INFORMATION = 4.
      final read = getSecurity(
        current(),
        6,
        4,
        nullptr,
        nullptr,
        oldAcl,
        nullptr,
        sd,
      );
      if (read != 0) return 'GetSecurityInfo win32=$read';
      // A null DACL already allows all access. Never synthesize a replacement.
      if (oldAcl.value == nullptr) return 'GetSecurityInfo null_dacl';
      if (convertSid(sidText, sid) == 0) {
        return 'ConvertStringSidToSidW win32=${lastError()}';
      }
      entry.ref
        ..permissions =
            0x1000 // PROCESS_QUERY_LIMITED_INFORMATION only.
        ..mode =
            1 // GRANT_ACCESS preserves existing ACEs, including denies.
        ..inheritance = 0;
      entry.ref.trustee
        ..form =
            0 // TRUSTEE_IS_SID
        ..type =
            5 // TRUSTEE_IS_WELL_KNOWN_GROUP
        ..name = sid.value;
      final merged = merge(1, entry, oldAcl.value, newAcl);
      if (merged != 0) return 'SetEntriesInAclW win32=$merged';
      if (newAcl.value == nullptr) return 'SetEntriesInAclW null_dacl';
      final applied = setSecurity(
        current(),
        6,
        4,
        nullptr,
        nullptr,
        newAcl.value,
        nullptr,
      );
      return applied == 0 ? null : 'SetSecurityInfo win32=$applied';
    } finally {
      if (newAcl.value != nullptr) free(newAcl.value);
      if (sid.value != nullptr) free(sid.value);
      if (sd.value != nullptr) free(sd.value);
      calloc.free(entry);
      calloc.free(sidText);
      calloc.free(sid);
      calloc.free(newAcl);
      calloc.free(oldAcl);
      calloc.free(sd);
    }
  }
}
