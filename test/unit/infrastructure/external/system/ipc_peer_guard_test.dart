import 'package:backup_database/infrastructure/external/system/ipc/ipc_peer_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IpcPeerGuard', () {
    test('should allow a peer with the same executable path', () {
      final guard = IpcPeerGuard(
        expectedImagePath: () =>
            r'C:\Program Files\Backup Database\backup_database.exe',
        resolveImagePath: (pid) {
          expect(pid, 42);
          return r'C:\Program Files\Backup Database\backup_database.exe';
        },
      );

      expect(guard.allowPeer(42), isTrue);
    });

    test('should reject the same basename from another directory', () {
      final guard = IpcPeerGuard(
        expectedImagePath: () =>
            r'C:\Program Files\Backup Database\backup_database.exe',
        resolveImagePath: (_) => r'D:\other\backup_database.exe',
      );

      expect(guard.allowPeer(42), isFalse);
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

    test('should compare full paths case-insensitively', () {
      final guard = IpcPeerGuard(
        expectedImagePath: () => r'C:\App\Backup_Database.EXE',
        resolveImagePath: (_) => r'c:\app\backup_database.exe',
      );

      expect(guard.allowPeer(3), isTrue);
    });

    test('should treat extended-length and 8.3 paths as the same exe', () {
      String expandShortPath(String path) {
        return path.replaceFirst('PROGRA~1', 'Program Files');
      }

      final guard = IpcPeerGuard(
        expectedImagePath: () =>
            r'C:\Program Files\Backup Database\backup_database.exe',
        resolveImagePath: (_) =>
            r'\\?\C:\PROGRA~1\Backup Database\backup_database.exe',
        expandLongPath: expandShortPath,
      );

      expect(guard.allowPeer(4), isTrue);
      expect(
        IpcPeerGuard.normalizePath(
          r'\\?\UNC\Server\Share\backup_database.exe',
        ),
        r'\\server\share\backup_database.exe',
      );
    });

    test(
      'should still reject another directory after short-name expansion',
      () {
        final guard = IpcPeerGuard(
          expectedImagePath: () =>
              r'C:\Program Files\Backup Database\backup_database.exe',
          resolveImagePath: (_) => r'C:\PROGRA~1\Other\backup_database.exe',
          expandLongPath: (path) =>
              path.replaceFirst('PROGRA~1', 'Program Files'),
        );

        expect(guard.allowPeer(4), isFalse);
      },
    );
  });
}
