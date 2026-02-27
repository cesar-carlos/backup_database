import 'package:backup_database/application/services/cached_license_validation_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockILicenseValidationService extends Mock
    implements ILicenseValidationService {}

class _MockIDeviceKeyService extends Mock implements IDeviceKeyService {}

void main() {
  late _MockILicenseValidationService delegate;
  late _MockIDeviceKeyService deviceKeyService;
  late CachedLicenseValidationService cached;

  const deviceKey = 'device-key-123';
  final license = License(
    id: 'lic-1',
    deviceKey: deviceKey,
    licenseKey: 'key-1',
    allowedFeatures: const ['f1'],
    createdAt: DateTime(2025),
  );

  setUp(() {
    delegate = _MockILicenseValidationService();
    deviceKeyService = _MockIDeviceKeyService();
    when(
      () => deviceKeyService.getDeviceKey(),
    ).thenAnswer((_) async => const rd.Success(deviceKey));
  });

  group('CachedLicenseValidationService.getCurrentLicense', () {
    test(
      'returns cached license within TTL without calling delegate again',
      () async {
        when(
          () => delegate.getCurrentLicense(),
        ).thenAnswer((_) async => rd.Success(license));

        cached = CachedLicenseValidationService(
          delegate: delegate,
          deviceKeyService: deviceKeyService,
        );

        final result1 = await cached.getCurrentLicense();
        final result2 = await cached.getCurrentLicense();

        expect(result1.isSuccess(), isTrue);
        expect(result1.getOrNull(), license);
        expect(result2.isSuccess(), isTrue);
        expect(result2.getOrNull(), license);
        verify(() => delegate.getCurrentLicense()).called(1);
      },
    );

    test('refetches after TTL expiration', () async {
      when(
        () => delegate.getCurrentLicense(),
      ).thenAnswer((_) async => rd.Success(license));

      cached = CachedLicenseValidationService(
        delegate: delegate,
        deviceKeyService: deviceKeyService,
        ttl: const Duration(milliseconds: 10),
      );

      await cached.getCurrentLicense();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await cached.getCurrentLicense();

      verify(() => delegate.getCurrentLicense()).called(2);
    });

    test(
      'invalidateLicenseCache clears cache and next call refetches',
      () async {
        when(
          () => delegate.getCurrentLicense(),
        ).thenAnswer((_) async => rd.Success(license));

        cached = CachedLicenseValidationService(
          delegate: delegate,
          deviceKeyService: deviceKeyService,
        );

        await cached.getCurrentLicense();
        cached.invalidateLicenseCache();
        await cached.getCurrentLicense();

        verify(() => delegate.getCurrentLicense()).called(2);
      },
    );

    test('propagates failure from delegate without caching success', () async {
      when(() => delegate.getCurrentLicense()).thenAnswer(
        (_) async => const rd.Failure(
          ValidationFailure(message: 'Licença expirada'),
        ),
      );

      cached = CachedLicenseValidationService(
        delegate: delegate,
        deviceKeyService: deviceKeyService,
      );

      final result = await cached.getCurrentLicense();

      expect(result.isError(), isTrue);
      verify(() => delegate.getCurrentLicense()).called(1);
    });

    test('propagates deviceKey failure without calling delegate', () async {
      when(() => deviceKeyService.getDeviceKey()).thenAnswer(
        (_) async => const rd.Failure(
          ServerFailure(message: 'Device key error'),
        ),
      );

      cached = CachedLicenseValidationService(
        delegate: delegate,
        deviceKeyService: deviceKeyService,
      );

      final result = await cached.getCurrentLicense();

      expect(result.isError(), isTrue);
      verifyNever(() => delegate.getCurrentLicense());
    });
  });

  group('CachedLicenseValidationService.isFeatureAllowed', () {
    test('uses cached getCurrentLicense for feature check', () async {
      when(
        () => delegate.getCurrentLicense(),
      ).thenAnswer((_) async => rd.Success(license));

      cached = CachedLicenseValidationService(
        delegate: delegate,
        deviceKeyService: deviceKeyService,
      );

      final hasF1 = await cached.isFeatureAllowed('f1');
      final hasF2 = await cached.isFeatureAllowed('f2');

      expect(hasF1.getOrNull(), isTrue);
      expect(hasF2.getOrNull(), isFalse);
      verify(() => delegate.getCurrentLicense()).called(1);
    });
  });

  group('CachedLicenseValidationService.validateLicense', () {
    test('delegates to underlying service', () async {
      when(
        () => delegate.validateLicense(
          any(named: 'licenseKey'),
          any(named: 'deviceKey'),
        ),
      ).thenAnswer((_) async => const rd.Success(true));

      cached = CachedLicenseValidationService(
        delegate: delegate,
        deviceKeyService: deviceKeyService,
      );

      final result = await cached.validateLicense('key', 'device');

      expect(result.getOrNull(), isTrue);
      verify(() => delegate.validateLicense('key', 'device')).called(1);
    });
  });
}
