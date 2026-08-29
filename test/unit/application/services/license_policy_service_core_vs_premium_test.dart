import 'package:backup_database/application/services/license_policy_service.dart';
import 'package:backup_database/application/services/license_trial_policy.dart';
import 'package:backup_database/application/services/license_validation_service.dart';
import 'package:backup_database/core/constants/license_trial_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_license_repository.dart';
import 'package:backup_database/domain/services/i_device_key_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockLicenseRepository extends Mock implements ILicenseRepository {}

class _MockDeviceKeyService extends Mock implements IDeviceKeyService {}

Schedule _fullLocalSchedule() {
  return Schedule(
    id: 's-core',
    name: 'Core',
    databaseConfigId: 'db1',
    databaseType: DatabaseType.sqlServer,
    scheduleType: 'daily',
    scheduleConfig: '{}',
    destinationIds: const ['local-1'],
    backupFolder: r'C:\temp',
  );
}

Schedule _differentialSchedule() {
  return Schedule(
    id: 's-diff',
    name: 'Diff',
    databaseConfigId: 'db1',
    databaseType: DatabaseType.sqlServer,
    scheduleType: 'daily',
    scheduleConfig: '{}',
    destinationIds: const ['local-1'],
    backupFolder: r'C:\temp',
    backupType: BackupType.differential,
  );
}

BackupDestination _localDestination() {
  return BackupDestination(
    id: 'local-1',
    name: 'Local',
    type: DestinationType.local,
    config: '{}',
  );
}

BackupDestination _driveDestination() {
  return BackupDestination(
    id: 'gd-1',
    name: 'Drive',
    type: DestinationType.googleDrive,
    config: '{}',
  );
}

void main() {
  const deviceKey = 'device-policy';
  final cut = LicenseTrialConstants.trialEndsExclusive;

  late _MockLicenseRepository repository;
  late _MockDeviceKeyService deviceKeyService;

  LicensePolicyService policyAt(DateTime now) {
    final validation = LicenseValidationService(
      licenseRepository: repository,
      deviceKeyService: deviceKeyService,
      trialPolicy: LicenseTrialPolicy(
        clock: () => now,
        endsAtExclusive: cut,
        forceEnded: false,
      ),
    );
    return LicensePolicyService(licenseValidationService: validation);
  }

  setUp(() {
    repository = _MockLicenseRepository();
    deviceKeyService = _MockDeviceKeyService();
    when(
      () => deviceKeyService.getDeviceKey(),
    ).thenAnswer((_) async => const rd.Success(deviceKey));
    when(() => repository.getByDeviceKey(deviceKey)).thenAnswer(
      (_) async => const rd.Failure(
        NotFoundFailure(message: 'Licença não encontrada'),
      ),
    );
  });

  group('LicensePolicyService core vs premium', () {
    test(
      'full + local during trial without stored license → Success',
      () async {
        final policy = policyAt(DateTime.utc(2027, 9, 30, 18));
        final result = await policy.validateExecutionCapabilities(
          _fullLocalSchedule(),
          [_localDestination()],
        );
        expect(result.isSuccess(), isTrue);
      },
    );

    test('full + local after trial without stored license → Success', () async {
      final policy = policyAt(DateTime.utc(2027, 10, 2, 3));
      final result = await policy.validateExecutionCapabilities(
        _fullLocalSchedule(),
        [_localDestination()],
      );
      expect(result.isSuccess(), isTrue);
    });

    test(
      'differential during trial without stored license → Success',
      () async {
        final policy = policyAt(DateTime.utc(2027, 9, 30, 18));
        final result = await policy.validateScheduleCapabilities(
          _differentialSchedule(),
        );
        expect(result.isSuccess(), isTrue);
      },
    );

    test('differential after trial without stored license → Failure', () async {
      final policy = policyAt(DateTime.utc(2027, 10, 2, 3));
      final result = await policy.validateScheduleCapabilities(
        _differentialSchedule(),
      );
      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as Failure;
      expect(failure.code, FailureCodes.licenseDenied);
    });

    test('Drive after trial without stored license → Failure', () async {
      final policy = policyAt(DateTime.utc(2027, 10, 2, 3));
      final result = await policy.validateDestinationCapabilities(
        _driveDestination(),
      );
      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as Failure;
      expect(failure.code, FailureCodes.licenseDenied);
    });
  });
}
