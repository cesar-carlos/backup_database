import 'package:backup_database/core/utils/firebird_runtime_version.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('firebirdRuntimeSupportsNbackupGuidMode', () {
    test('returns true for hint v40', () {
      expect(
        firebirdRuntimeSupportsNbackupGuidMode(
          serverVersionHint: FirebirdServerVersionHint.v40,
        ),
        isTrue,
      );
    });

    test('returns false for hint v25 and v30', () {
      expect(
        firebirdRuntimeSupportsNbackupGuidMode(
          serverVersionHint: FirebirdServerVersionHint.v25,
        ),
        isFalse,
      );
      expect(
        firebirdRuntimeSupportsNbackupGuidMode(
          serverVersionHint: FirebirdServerVersionHint.v30,
        ),
        isFalse,
      );
    });

    test('returns true for auto when gbak tagline is WI-V4', () {
      expect(
        firebirdRuntimeSupportsNbackupGuidMode(
          serverVersionHint: FirebirdServerVersionHint.auto,
          gbakWiTagline: 'WI-V4.0.5.3140 Firebird 4.0',
        ),
        isTrue,
      );
    });

    test('returns false for auto when gbak tagline is WI-V3', () {
      expect(
        firebirdRuntimeSupportsNbackupGuidMode(
          serverVersionHint: FirebirdServerVersionHint.auto,
          gbakWiTagline: 'WI-V3.0.11.33703 Firebird 3.0',
        ),
        isFalse,
      );
    });
  });

  group('firebirdGbakUsesKeyNameEncryption', () {
    test('matches nbackup GUID mode for v40', () {
      expect(
        firebirdGbakUsesKeyNameEncryption(
          serverVersionHint: FirebirdServerVersionHint.v40,
        ),
        isTrue,
      );
    });

    test('returns false for v30', () {
      expect(
        firebirdGbakUsesKeyNameEncryption(
          serverVersionHint: FirebirdServerVersionHint.v30,
        ),
        isFalse,
      );
    });
  });
}
