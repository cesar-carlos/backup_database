import 'package:backup_database/presentation/managers/window_manager_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('keepsProcessWhenWindowCloses', () {
    test('should keep the process when minimize to tray is enabled', () {
      final keeps = keepsProcessWhenWindowCloses(
        minimizeToTray: true,
        closeToTray: false,
      );

      expect(keeps, isTrue);
    });

    test('should keep the process when close to tray is enabled', () {
      final keeps = keepsProcessWhenWindowCloses(
        minimizeToTray: false,
        closeToTray: true,
      );

      expect(keeps, isTrue);
    });

    test('should quit when both tray options are disabled', () {
      final keeps = keepsProcessWhenWindowCloses(
        minimizeToTray: false,
        closeToTray: false,
      );

      expect(keeps, isFalse);
    });
  });
}
