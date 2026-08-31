import 'package:backup_database/infrastructure/external/system/ipc/ipc_peer_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IpcPeerGuard', () {
    test('should allow a peer with the same executable basename', () {
      final guard = IpcPeerGuard(
        expectedImagePath: () =>
            r'C:\Program Files\Backup Database\backup_database.exe',
        resolveImagePath: (pid) {
          expect(pid, 42);
          return r'D:\other\backup_database.exe';
        },
      );

      expect(guard.allowPeer(42), isTrue);
    });

    test('should reject a peer with a different basename', () {
      final guard = IpcPeerGuard(
        expectedImagePath: () => r'C:\app\backup_database.exe',
        resolveImagePath: (_) => r'C:\Windows\System32\cmd.exe',
      );

      expect(guard.allowPeer(7), isFalse);
    });

    test('should reject a missing image path or non-positive pid', () {
      final guard = IpcPeerGuard(
        expectedImagePath: () => r'C:\app\backup_database.exe',
        resolveImagePath: (_) => null,
      );

      expect(guard.allowPeer(1), isFalse);
      expect(guard.allowPeer(0), isFalse);
    });

    test('should compare basenames case-insensitively', () {
      final guard = IpcPeerGuard(
        expectedImagePath: () => r'C:\App\Backup_Database.EXE',
        resolveImagePath: (_) => r'd:\tmp\backup_database.exe',
      );

      expect(guard.allowPeer(3), isTrue);
    });
  });
}
