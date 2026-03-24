import 'package:backup_database/core/bootstrap/machine_scope_r1_legacy_paths_hint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MachineScopeR1LegacyPathsHint', () {
    test('dismissalSignature is order independent', () {
      const a = MachineScopeR1LegacyPathsHint(
        otherProfilesLegacySqlitePaths: <String>['z', 'a', 'm'],
      );
      const b = MachineScopeR1LegacyPathsHint(
        otherProfilesLegacySqlitePaths: <String>['a', 'm', 'z'],
      );
      expect(a.dismissalSignature, b.dismissalSignature);
    });

    test('hasDetectedOtherProfiles is false when empty', () {
      const hint = MachineScopeR1LegacyPathsHint(
        otherProfilesLegacySqlitePaths: <String>[],
      );
      expect(hint.hasDetectedOtherProfiles, isFalse);
      expect(hint.dismissalSignature, '');
    });
  });
}
