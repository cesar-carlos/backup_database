import 'package:backup_database/core/utils/elevated_legacy_profile_scan_outcome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final p.Context _windowsPathContext = p.Context(
  style: p.Style.windows,
);

void main() {
  group('decodeElevatedLegacyProfileScanJson', () {
    test('parses schemaVersion 1 and normalizes paths', () {
      final o = decodeElevatedLegacyProfileScanJson(
        '{"schemaVersion":1,"paths":["C:/Users/Bob/AppData/Roaming/Backup '
            'Database"],"scannedAtUtc":"2020-01-01T00:00:00Z"}',
        '',
        methodUsed: LegacyElevatedScanMethod.nativeExecutable,
      );
      expect(o.userCancelledOrFailed, isFalse);
      expect(o.paths, hasLength(1));
      expect(
        _windowsPathContext.normalize(o.paths.single),
        _windowsPathContext.normalize(
          r'C:\Users\Bob\AppData\Roaming\Backup Database',
        ),
      );
      expect(o.methodUsed, LegacyElevatedScanMethod.nativeExecutable);
    });

    test('rejects payload without schemaVersion', () {
      final o = decodeElevatedLegacyProfileScanJson(
        '{"paths":["D:/x"],"scannedAtUtc":"t"}',
        '',
        methodUsed: LegacyElevatedScanMethod.powershell,
      );
      expect(o.userCancelledOrFailed, isTrue);
      expect(o.failureKind, ElevatedLegacyScanFailureKind.invalidJson);
    });

    test('rejects unknown schemaVersion', () {
      final o = decodeElevatedLegacyProfileScanJson(
        '{"schemaVersion":99,"paths":[]}',
        '',
        methodUsed: LegacyElevatedScanMethod.nativeExecutable,
      );
      expect(o.userCancelledOrFailed, isTrue);
      expect(o.failureKind, ElevatedLegacyScanFailureKind.invalidJson);
    });

    test('rejects malformed JSON', () {
      final o = decodeElevatedLegacyProfileScanJson(
        '{not json',
        'err',
        methodUsed: LegacyElevatedScanMethod.powershell,
      );
      expect(o.userCancelledOrFailed, isTrue);
      expect(o.failureKind, ElevatedLegacyScanFailureKind.invalidJson);
      expect(o.stderr, 'err');
    });
  });
}
