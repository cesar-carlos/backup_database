import 'package:backup_database/application/services/license_trial_policy.dart';
import 'package:backup_database/application/services/license_validation_service.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/license_trial_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/repositories/i_license_repository.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
import 'package:backup_database/domain/services/i_revocation_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockLicenseRepository extends Mock implements ILicenseRepository {}

class _MockDeviceKeyService extends Mock implements IDeviceKeyService {}

class _MockRevocationChecker extends Mock implements IRevocationChecker {}

void main() {
  const deviceKey = 'device-trial';
  final cut = LicenseTrialConstants.trialEndsExclusive;

  late _MockLicenseRepository repository;
  late _MockDeviceKeyService deviceKeyService;
  late _MockRevocationChecker revocationChecker;

  LicenseTrialPolicy trialAt(DateTime now, {bool forceEnded = false}) {
    return LicenseTrialPolicy(
      clock: () => now,
      endsAtExclusive: cut,
      forceEnded: forceEnded,
    );
  }

  LicenseValidationService serviceFor(LicenseTrialPolicy policy) {
    return LicenseValidationService(
      licenseRepository: repository,
      deviceKeyService: deviceKeyService,
      revocationChecker: revocationChecker,
      trialPolicy: policy,
    );
  }

  setUp(() {
    repository = _MockLicenseRepository();
    deviceKeyService = _MockDeviceKeyService();
    revocationChecker = _MockRevocationChecker();
    when(
      () => deviceKeyService.getDeviceKey(),
    ).thenAnswer((_) async => const rd.Success(deviceKey));
    when(() => revocationChecker.isRevoked(deviceKey)).thenAnswer(
      (_) async => false,
    );
  });

  group('LicenseValidationService.getCurrentLicense trial', () {
    test('returns synthetic when nothing stored and trial is active', () async {
      when(() => repository.getByDeviceKey(deviceKey)).thenAnswer(
        (_) async => const rd.Failure(
          NotFoundFailure(message: 'Licença não encontrada'),
        ),
      );
      final service = serviceFor(
        trialAt(DateTime.utc(2027, 9, 30, 18)),
      );

      final result = await service.getCurrentLicense();
      expect(result.isSuccess(), isTrue);
      final license = result.getOrNull()!;
      expect(license.isTrial, isTrue);
      expect(license.id, LicenseTrialConstants.trialLicenseId);
      expect(license.hasFeature(LicenseFeatures.googleDrive), isTrue);
    });

    test('stored expired + trial active → synthetic, not Failure', () async {
      final expired = License(
        id: 'old',
        deviceKey: deviceKey,
        licenseKey: 'expired-key',
        allowedFeatures: const [LicenseFeatures.emailNotification],
        expiresAt: DateTime.utc(2026),
      );
      when(() => repository.getByDeviceKey(deviceKey)).thenAnswer(
        (_) async => rd.Success(expired),
      );
      final service = serviceFor(
        trialAt(DateTime.utc(2027, 9, 30, 18)),
      );

      final result = await service.getCurrentLicense();
      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull()!.isTrial, isTrue);
    });

    test('valid premium is not unioned with trial', () async {
      final premium = License(
        id: 'premium',
        deviceKey: deviceKey,
        licenseKey: 'premium-key',
        allowedFeatures: const [LicenseFeatures.emailNotification],
        expiresAt: DateTime.utc(2028),
      );
      when(() => repository.getByDeviceKey(deviceKey)).thenAnswer(
        (_) async => rd.Success(premium),
      );
      final service = serviceFor(
        trialAt(DateTime.utc(2027, 9, 30, 18)),
      );

      final result = await service.getCurrentLicense();
      expect(result.isSuccess(), isTrue);
      final license = result.getOrNull()!;
      expect(license.isTrial, isFalse);
      expect(license.hasFeature(LicenseFeatures.emailNotification), isTrue);
      expect(license.hasFeature(LicenseFeatures.googleDrive), isFalse);
    });

    test('revoked device does not get trial', () async {
      when(() => revocationChecker.isRevoked(deviceKey)).thenAnswer(
        (_) async => true,
      );
      when(() => repository.getByDeviceKey(deviceKey)).thenAnswer(
        (_) async => const rd.Failure(
          NotFoundFailure(message: 'Licença não encontrada'),
        ),
      );
      final service = serviceFor(
        trialAt(DateTime.utc(2027, 9, 30, 18)),
      );

      final result = await service.getCurrentLicense();
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull().toString(), contains('revogada'));
    });

    test('after cut with no stored → NotFound', () async {
      when(() => repository.getByDeviceKey(deviceKey)).thenAnswer(
        (_) async => const rd.Failure(
          NotFoundFailure(message: 'Licença não encontrada'),
        ),
      );
      final service = serviceFor(
        trialAt(DateTime.utc(2027, 10, 2, 3)),
      );

      final result = await service.getCurrentLicense();
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<NotFoundFailure>());
    });

    test('after cut with expired stored → expired Failure', () async {
      final expired = License(
        id: 'old',
        deviceKey: deviceKey,
        licenseKey: 'expired-key',
        allowedFeatures: const [LicenseFeatures.emailNotification],
        expiresAt: DateTime.utc(2026),
      );
      when(() => repository.getByDeviceKey(deviceKey)).thenAnswer(
        (_) async => rd.Success(expired),
      );
      final service = serviceFor(
        trialAt(DateTime.utc(2027, 10, 2, 3)),
      );

      final result = await service.getCurrentLicense();
      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull().toString(), contains('expirada'));
    });

    test('getStoredLicense never returns synthetic', () async {
      when(() => repository.getByDeviceKey(deviceKey)).thenAnswer(
        (_) async => const rd.Failure(
          NotFoundFailure(message: 'Licença não encontrada'),
        ),
      );
      final service = serviceFor(
        trialAt(DateTime.utc(2027, 9, 30, 18)),
      );

      final stored = await service.getStoredLicense();
      final current = await service.getCurrentLicense();
      expect(stored.isError(), isTrue);
      expect(current.getOrNull()!.isTrial, isTrue);
    });
  });
}
