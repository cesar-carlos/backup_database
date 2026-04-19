import 'package:backup_database/core/utils/byte_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ByteFormat.format', () {
    test('formats bytes below 1 KB without conversion', () {
      expect(ByteFormat.format(0), equals('0 B'));
      expect(ByteFormat.format(1), equals('1 B'));
      expect(ByteFormat.format(512), equals('512 B'));
      expect(ByteFormat.format(1023), equals('1023 B'));
    });

    test('formats bytes from 1 KB up to but not including 1 MB', () {
      expect(ByteFormat.format(1024), equals('1.00 KB'));
      expect(ByteFormat.format(1536), equals('1.50 KB'));
      expect(ByteFormat.format(1024 * 1024 - 1), equals('1024.00 KB'));
    });

    test('formats bytes from 1 MB up to but not including 1 GB', () {
      expect(ByteFormat.format(1024 * 1024), equals('1.00 MB'));
      expect(
        ByteFormat.format((1.5 * 1024 * 1024).toInt()),
        equals('1.50 MB'),
      );
      expect(
        ByteFormat.format(1024 * 1024 * 1024 - 1),
        equals('1024.00 MB'),
      );
    });

    test('formats bytes >= 1 GB in GB', () {
      expect(ByteFormat.format(1024 * 1024 * 1024), equals('1.00 GB'));
      expect(
        ByteFormat.format(2 * 1024 * 1024 * 1024),
        equals('2.00 GB'),
      );
      expect(
        ByteFormat.format((1.5 * 1024 * 1024 * 1024).toInt()),
        equals('1.50 GB'),
      );
    });

    test('uses exactly 2 decimal places for KB/MB/GB (not 1, not 3)', () {
      // Regression guard: o FTP service usava 1 decimal sem espaço
      // (ex: "5.4MB"); a versão centralizada padroniza em 2 decimais
      // com espaço. Não voltar atrás.
      final result = ByteFormat.format(1500);
      expect(result, contains('.46'));
      expect(result, contains(' KB'));
      expect(
        result,
        isNot(matches(r'^\d+\.\d{1}\s')),
        reason: 'must use 2 decimal places, not 1',
      );
      expect(
        result,
        isNot(matches(r'^\d+\.\d{3}\s')),
        reason: 'must use 2 decimal places, not 3',
      );
    });
  });

  group('ByteFormat.speedMbPerSec', () {
    test('returns 0 when duration is zero (avoid division by zero)', () {
      expect(ByteFormat.speedMbPerSec(1024 * 1024, 0), equals(0));
    });

    test('returns 0 when duration is negative (defensive)', () {
      expect(ByteFormat.speedMbPerSec(1024 * 1024, -5), equals(0));
    });

    test('computes MB/s from bytes and seconds', () {
      // 10 MB em 5 segundos = 2 MB/s
      expect(
        ByteFormat.speedMbPerSec(10 * 1024 * 1024, 5),
        equals(2.0),
      );
    });

    test('computes fractional speeds correctly', () {
      // 1 MB em 4 segundos = 0.25 MB/s
      expect(
        ByteFormat.speedMbPerSec(1024 * 1024, 4),
        closeTo(0.25, 0.0001),
      );
    });
  });

  group('ByteFormat.speedMbPerSecFromDuration', () {
    test('delegates to speedMbPerSec using duration.inSeconds', () {
      const sizeBytes = 10 * 1024 * 1024;
      const duration = Duration(seconds: 5);

      expect(
        ByteFormat.speedMbPerSecFromDuration(sizeBytes, duration),
        equals(ByteFormat.speedMbPerSec(sizeBytes, 5)),
      );
    });

    test('returns 0 for Duration.zero', () {
      expect(
        ByteFormat.speedMbPerSecFromDuration(1024 * 1024, Duration.zero),
        equals(0),
      );
    });

    test('truncates sub-second durations to 0 (inSeconds rounds down)', () {
      // 500 ms.inSeconds == 0 → returns 0 by zero-guard
      // Esse comportamento é intencional: chamadas com durações muito
      // curtas (< 1s) não têm precisão suficiente para reportar throughput.
      expect(
        ByteFormat.speedMbPerSecFromDuration(
          1024 * 1024,
          const Duration(milliseconds: 500),
        ),
        equals(0),
      );
    });
  });
}
