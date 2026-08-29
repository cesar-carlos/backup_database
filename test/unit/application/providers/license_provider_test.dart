import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/services/i_license_cache_invalidator.dart';
import 'package:backup_database/application/services/license_generation_service.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/license_trial_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/repositories/i_license_repository.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockLicenseValidationService extends Mock
    implements ILicenseValidationService {}

class _MockLicenseGenerationService extends Mock
    implements LicenseGenerationService {}

class _MockLicenseRepository extends Mock implements ILicenseRepository {}

class _MockDeviceKeyService extends Mock implements IDeviceKeyService {}

class _MockLicenseCacheInvalidator extends Mock
    implements ILicenseCacheInvalidator {}

void main() {
  late _MockLicenseValidationService validationService;
  late _MockLicenseGenerationService generationService;
  late _MockLicenseRepository licenseRepository;
  late _MockDeviceKeyService deviceKeyService;
  late LicenseProvider provider;

  const deviceKey = 'device-key-123';
  final existingLicense = License(
    id: 'existing-id',
    deviceKey: deviceKey,
    licenseKey: 'old-key',
    allowedFeatures: const ['feature1'],
    createdAt: DateTime(2025),
  );
  final newLicense = License(
    deviceKey: deviceKey,
    licenseKey: 'new-key',
    allowedFeatures: const ['feature1', 'feature2'],
  );
  final trialLicense = License(
    id: LicenseTrialConstants.trialLicenseId,
    deviceKey: deviceKey,
    licenseKey: LicenseTrialConstants.trialLicenseKey,
    allowedFeatures: LicenseFeatures.allFeatures,
    expiresAt: LicenseTrialConstants.trialEndsExclusive,
  );

  setUpAll(() {
    registerFallbackValue(existingLicense);
    registerFallbackValue(newLicense);
  });

  setUp(() {
    validationService = _MockLicenseValidationService();
    generationService = _MockLicenseGenerationService();
    licenseRepository = _MockLicenseRepository();
    deviceKeyService = _MockDeviceKeyService();

    when(
      () => deviceKeyService.getDeviceKey(),
    ).thenAnswer((_) async => const rd.Success(deviceKey));
    when(() => validationService.getStoredLicense()).thenAnswer(
      (_) async => const rd.Failure(
        NotFoundFailure(message: 'Licença não encontrada'),
      ),
    );
    when(() => validationService.getCurrentLicense()).thenAnswer(
      (_) async => const rd.Failure(
        NotFoundFailure(message: 'Licença não encontrada'),
      ),
    );

    provider = LicenseProvider(
      validationService: validationService,
      generationService: generationService,
      licenseRepository: licenseRepository,
      deviceKeyService: deviceKeyService,
    );
  });

  LicenseProvider buildProvider() {
    return LicenseProvider(
      validationService: validationService,
      generationService: generationService,
      licenseRepository: licenseRepository,
      deviceKeyService: deviceKeyService,
    );
  }

  group('LicenseProvider.validateAndSaveLicense', () {
    test(
      'calls upsertByDeviceKey and succeeds when license is valid',
      () async {
        when(
          () => generationService.createLicenseFromKey(
            licenseKey: any(named: 'licenseKey'),
            deviceKey: any(named: 'deviceKey'),
          ),
        ).thenAnswer((_) async => rd.Success(newLicense));

        when(
          () => licenseRepository.upsertByDeviceKey(any()),
        ).thenAnswer((_) async => rd.Success(newLicense));
        when(() => validationService.getCurrentLicense()).thenAnswer(
          (_) async => rd.Success(newLicense),
        );

        provider.setDeviceKey(deviceKey);
        final result = await provider.validateAndSaveLicense('new-license-key');

        expect(result, isTrue);

        verify(() => licenseRepository.upsertByDeviceKey(any())).called(1);
      },
    );

    test(
      'invalidates license cache when save succeeds and cacheInvalidator set',
      () async {
        final cacheInvalidator = _MockLicenseCacheInvalidator();
        provider = LicenseProvider(
          validationService: validationService,
          generationService: generationService,
          licenseRepository: licenseRepository,
          deviceKeyService: deviceKeyService,
          cacheInvalidator: cacheInvalidator,
        );

        when(
          () => generationService.createLicenseFromKey(
            licenseKey: any(named: 'licenseKey'),
            deviceKey: any(named: 'deviceKey'),
          ),
        ).thenAnswer((_) async => rd.Success(newLicense));

        when(
          () => licenseRepository.upsertByDeviceKey(any()),
        ).thenAnswer((_) async => rd.Success(newLicense));
        when(() => validationService.getCurrentLicense()).thenAnswer(
          (_) async => rd.Success(newLicense),
        );

        provider.setDeviceKey(deviceKey);
        await provider.validateAndSaveLicense('new-license-key');

        verify(cacheInvalidator.invalidateLicenseCache).called(1);
      },
    );

    test(
      'returns false when upsertByDeviceKey fails',
      () async {
        when(
          () => generationService.createLicenseFromKey(
            licenseKey: any(named: 'licenseKey'),
            deviceKey: any(named: 'deviceKey'),
          ),
        ).thenAnswer((_) async => rd.Success(newLicense));

        when(
          () => licenseRepository.upsertByDeviceKey(any()),
        ).thenAnswer(
          (_) async => const rd.Failure(
            DatabaseFailure(message: 'Erro ao salvar licença'),
          ),
        );

        provider.setDeviceKey(deviceKey);
        final result = await provider.validateAndSaveLicense('new-license-key');

        expect(result, isFalse);
        expect(provider.error, contains('Erro ao salvar licença'));
      },
    );
  });

  group('LicenseProvider effective vs stored', () {
    test('trial without stored unlocks catalog features', () async {
      when(() => validationService.getCurrentLicense()).thenAnswer(
        (_) async => rd.Success(trialLicense),
      );
      provider = buildProvider();
      await provider.loadLicense();

      expect(provider.isLicenseLoaded, isTrue);
      expect(provider.hasValidLicense, isTrue);
      expect(provider.isTrialActive, isTrue);
      expect(
        provider.isFeatureUnlocked(LicenseFeatures.googleDrive),
        isTrue,
      );
    });

    test('stored expired + trial still unlocks features', () async {
      final expired = License(
        id: 'old',
        deviceKey: deviceKey,
        licenseKey: 'expired-key',
        allowedFeatures: const [LicenseFeatures.emailNotification],
        expiresAt: DateTime.utc(2026),
      );
      when(() => validationService.getStoredLicense()).thenAnswer(
        (_) async => rd.Success(expired),
      );
      when(() => validationService.getCurrentLicense()).thenAnswer(
        (_) async => rd.Success(trialLicense),
      );
      provider = buildProvider();
      await provider.loadLicense();

      expect(provider.storedLicense!.isExpired, isTrue);
      expect(provider.isFeatureUnlocked(LicenseFeatures.dropbox), isTrue);
    });

    test('after trial without premium locks premium features', () async {
      when(() => validationService.getCurrentLicense()).thenAnswer(
        (_) async => const rd.Failure(
          NotFoundFailure(message: 'Licença não encontrada'),
        ),
      );
      provider = buildProvider();
      await provider.loadLicense();

      expect(provider.hasValidLicense, isFalse);
      expect(provider.isTrialEndedWithoutPremium, isTrue);
      expect(
        provider.isFeatureUnlocked(LicenseFeatures.googleDrive),
        isFalse,
      );
    });

    test('revoked device locks features', () async {
      when(() => validationService.getStoredLicense()).thenAnswer(
        (_) async => rd.Success(existingLicense),
      );
      when(() => validationService.getCurrentLicense()).thenAnswer(
        (_) async => const rd.Failure(
          ValidationFailure(message: 'Licença revogada'),
        ),
      );
      provider = buildProvider();
      await provider.loadLicense();

      expect(provider.isDeviceRevoked, isTrue);
      expect(provider.hasValidLicense, isFalse);
      expect(
        provider.isFeatureUnlocked(LicenseFeatures.googleDrive),
        isFalse,
      );
    });
  });
}
