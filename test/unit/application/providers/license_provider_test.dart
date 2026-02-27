import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/application/services/i_license_cache_invalidator.dart';
import 'package:backup_database/application/services/license_generation_service.dart';
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

  setUpAll(() {
    registerFallbackValue(existingLicense);
    registerFallbackValue(newLicense);
  });

  setUp(() {
    validationService = _MockLicenseValidationService();
    generationService = _MockLicenseGenerationService();
    licenseRepository = _MockLicenseRepository();
    deviceKeyService = _MockDeviceKeyService();

    when(() => deviceKeyService.getDeviceKey())
        .thenAnswer((_) async => const rd.Success(deviceKey));

    provider = LicenseProvider(
      validationService: validationService,
      generationService: generationService,
      licenseRepository: licenseRepository,
      deviceKeyService: deviceKeyService,
    );
  });

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
}
