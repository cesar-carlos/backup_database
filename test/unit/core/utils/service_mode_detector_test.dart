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

    test('matchesServiceArgument should require exact --run-as-service', () {
      expect(
        ServiceModeDetector.matchesServiceArgument(const ['--run-as-service']),
        isTrue,
      );
      expect(
        ServiceModeDetector.matchesServiceArgument(const ['--mode=server']),
        isFalse,
      );
      expect(
        ServiceModeDetector.matchesServiceArgument(const <String>[]),
        isFalse,
      );
    });

    test('matchesServiceModeEnvValue should accept server, 1 and true', () {
      expect(ServiceModeDetector.matchesServiceModeEnvValue('server'), isTrue);
      expect(ServiceModeDetector.matchesServiceModeEnvValue('1'), isTrue);
      expect(ServiceModeDetector.matchesServiceModeEnvValue('true'), isTrue);
      expect(
        ServiceModeDetector.matchesServiceModeEnvValue(' SERVER '),
        isTrue,
      );
      expect(ServiceModeDetector.matchesServiceModeEnvValue('True'), isTrue);
    });

    test('matchesServiceModeEnvValue should reject unknown values', () {
      expect(ServiceModeDetector.matchesServiceModeEnvValue(null), isFalse);
      expect(ServiceModeDetector.matchesServiceModeEnvValue(''), isFalse);
      expect(ServiceModeDetector.matchesServiceModeEnvValue('ui'), isFalse);
      expect(
        ServiceModeDetector.matchesServiceModeEnvValue('yes'),
        isFalse,
      );
    });

    test('validServiceModeValues should match the C++ runner set', () {
      expect(
        ServiceModeDetector.validServiceModeValues,
        equals({'server', '1', 'true'}),
      );
      expect(
        ServiceModeDetector.serviceArgFlag,
        equals('--run-as-service'),
      );
    });
  });
}
