import 'package:backup_database/core/utils/windows_legacy_profile_elevated_scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('mergeLegacyProfilePathsExcludingCurrentUser', () {
    test('merges elevated and normal scan and dedupes', () async {
      const bob = r'C:\Users\Bob\AppData\Roaming\Backup Database';
      const alice = r'C:\Users\Alice\AppData\Roaming\Backup Database';
      final merged = await mergeLegacyProfilePathsExcludingCurrentUser(
        elevatedPaths: <String>[bob],
        normalScanForTest: () async => <String>[bob, alice],
        currentUserLegacyPathOverrideForTest: alice,
      );
      expect(merged.length, 1);
      expect(p.normalize(merged.single), p.normalize(bob));
    });
  });
}
