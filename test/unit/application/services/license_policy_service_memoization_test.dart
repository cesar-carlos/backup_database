import 'package:backup_database/application/services/license_policy_service.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockILicenseValidationService extends Mock
    implements ILicenseValidationService {}

void main() {
  late _MockILicenseValidationService validationService;
  late LicensePolicyService policyService;

  setUp(() {
    validationService = _MockILicenseValidationService();
    policyService = LicensePolicyService(
      licenseValidationService: validationService,
    );
  });

  group('LicensePolicyService run context memoization', () {
    test('memoizes isFeatureAllowed within same runId', () async {
      when(() => validationService.isFeatureAllowed(any()))
          .thenAnswer((_) async => const rd.Success(true));

      policyService.setRunContext('run-1');

      final schedule = Schedule(
        id: 's1',
        name: 'Test',
        databaseConfigId: 'db1',
        databaseType: DatabaseType.sqlServer,
        scheduleType: 'interval',
        scheduleConfig: '{}',
        destinationIds: const [],
        backupFolder: r'C:\temp',
        backupType: BackupType.differential,
        enableChecksum: true,
      );

      final result1 = await policyService.validateScheduleCapabilities(schedule);
      final result2 = await policyService.validateScheduleCapabilities(schedule);

      expect(result1.isSuccess(), isTrue);
      expect(result2.isSuccess(), isTrue);
      verify(() => validationService.isFeatureAllowed(any())).called(3);
    });

    test('clearRunContext clears memoization cache', () async {
      when(() => validationService.isFeatureAllowed(any()))
          .thenAnswer((_) async => const rd.Success(true));

      policyService.setRunContext('run-1');

      final dest = BackupDestination(
        id: 'd1',
        name: 'GD',
        type: DestinationType.googleDrive,
        config: '{}',
      );

      await policyService.validateDestinationCapabilities(dest);
      policyService.clearRunContext();
      await policyService.validateDestinationCapabilities(dest);

      verify(() => validationService.isFeatureAllowed(LicenseFeatures.googleDrive))
          .called(2);
    });

    test('without run context delegates every call', () async {
      when(() => validationService.isFeatureAllowed(any()))
          .thenAnswer((_) async => const rd.Success(true));

      final dest = BackupDestination(
        id: 'd1',
        name: 'GD',
        type: DestinationType.googleDrive,
        config: '{}',
      );

      await policyService.validateDestinationCapabilities(dest);
      await policyService.validateDestinationCapabilities(dest);

      verify(() => validationService.isFeatureAllowed(LicenseFeatures.googleDrive))
          .called(2);
    });
  });
}
