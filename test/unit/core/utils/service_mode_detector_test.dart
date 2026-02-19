import 'package:backup_database/core/utils/service_mode_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceModeDetector', () {
    test(
      'isSessionLookupSuccessfulForTest should return true for non-zero',
      () {
        final result = ServiceModeDetector.isSessionLookupSuccessfulForTest(1);

        expect(result, isTrue);
      },
    );

    test('isSessionLookupSuccessfulForTest should return false for zero', () {
      final result = ServiceModeDetector.isSessionLookupSuccessfulForTest(0);

      expect(result, isFalse);
    });

    test('isServiceSessionIdForTest should return true for session zero', () {
      final result = ServiceModeDetector.isServiceSessionIdForTest(0);

      expect(result, isTrue);
    });

    test(
      'isServiceSessionIdForTest should return false for non-zero session',
      () {
        final result = ServiceModeDetector.isServiceSessionIdForTest(2);

        expect(result, isFalse);
      },
    );
  });
}
