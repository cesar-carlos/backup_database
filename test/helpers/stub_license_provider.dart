import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../unit/helpers/mock_repositories.dart';

LicenseProvider stubLicenseProvider() {
  final validation = MockLicenseValidationService();
  final repository = MockLicenseRepository();
  final deviceKey = MockDeviceKeyService();
  final generation = MockLicenseGenerationService();

  when(validation.getStoredLicense).thenAnswer(
    (_) async => const rd.Failure(
      NotFoundFailure(message: 'No license'),
    ),
  );
  when(validation.getCurrentLicense).thenAnswer(
    (_) async => const rd.Failure(
      NotFoundFailure(message: 'No license'),
    ),
  );
  when(deviceKey.getDeviceKey).thenAnswer(
    (_) async => const rd.Success('test-device-key'),
  );

  return LicenseProvider(
    validationService: validation,
    generationService: generation,
    licenseRepository: repository,
    deviceKeyService: deviceKey,
  );
}
