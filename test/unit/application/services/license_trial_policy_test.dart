import 'package:backup_database/application/services/license_trial_policy.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/license_trial_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LicenseTrialPolicy', () {
    final cut = LicenseTrialConstants.trialEndsExclusive;

    test('is active at 2027-09-30T15:00-03:00', () {
      final policy = LicenseTrialPolicy(
        clock: () => DateTime.utc(2027, 9, 30, 18),
        endsAtExclusive: cut,
        forceEnded: false,
      );
      expect(policy.isActive(), isTrue);
    });

    test('is ended at 2027-10-02T00:00-03:00', () {
      final policy = LicenseTrialPolicy(
        clock: () => DateTime.utc(2027, 10, 2, 3),
        endsAtExclusive: cut,
        forceEnded: false,
      );
      expect(policy.isActive(), isFalse);
    });

    test('forceEnded overrides clock', () {
      final policy = LicenseTrialPolicy(
        clock: () => DateTime.utc(2027, 9),
        endsAtExclusive: cut,
        forceEnded: true,
      );
      expect(policy.isActive(), isFalse);
    });

    test('syntheticLicense is stable and includes catalog', () {
      final policy = LicenseTrialPolicy(
        clock: () => DateTime.utc(2027, 9),
        endsAtExclusive: cut,
        forceEnded: false,
      );
      final a = policy.syntheticLicense(deviceKey: 'dev-1');
      final b = policy.syntheticLicense(deviceKey: 'dev-1');
      expect(a.id, LicenseTrialConstants.trialLicenseId);
      expect(a.licenseKey, LicenseTrialConstants.trialLicenseKey);
      expect(a.isTrial, isTrue);
      expect(a.allowedFeatures, LicenseFeatures.allFeatures);
      expect(a, equals(b));
      expect(a.allowedFeatures.contains(LicenseFeatures.googleDrive), isTrue);
    });

    test('reminder window is last 30 days', () {
      final inside = LicenseTrialPolicy(
        clock: () => cut.subtract(const Duration(days: 10)),
        endsAtExclusive: cut,
        forceEnded: false,
      );
      final outside = LicenseTrialPolicy(
        clock: () => cut.subtract(const Duration(days: 40)),
        endsAtExclusive: cut,
        forceEnded: false,
      );
      expect(inside.isReminderWindow, isTrue);
      expect(outside.isReminderWindow, isFalse);
    });
  });
}
