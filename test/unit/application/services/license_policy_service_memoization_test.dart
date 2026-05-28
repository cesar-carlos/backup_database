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
      when(
        () => validationService.isFeatureAllowed(any()),
      ).thenAnswer((_) async => const rd.Success(true));

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

      final result1 = await policyService.validateScheduleCapabilities(
        schedule,
      );
      final result2 = await policyService.validateScheduleCapabilities(
        schedule,
      );

      expect(result1.isSuccess(), isTrue);
      expect(result2.isSuccess(), isTrue);
      verify(() => validationService.isFeatureAllowed(any())).called(3);
    });

    test('clearRunContext clears memoization cache', () async {
      when(
        () => validationService.isFeatureAllowed(any()),
      ).thenAnswer((_) async => const rd.Success(true));

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

      verify(
        () => validationService.isFeatureAllowed(LicenseFeatures.googleDrive),
      ).called(2);
    });

    test('without run context delegates every call', () async {
      when(
        () => validationService.isFeatureAllowed(any()),
      ).thenAnswer((_) async => const rd.Success(true));

      final dest = BackupDestination(
        id: 'd1',
        name: 'GD',
        type: DestinationType.googleDrive,
        config: '{}',
      );

      await policyService.validateDestinationCapabilities(dest);
      await policyService.validateDestinationCapabilities(dest);

      verify(
        () => validationService.isFeatureAllowed(LicenseFeatures.googleDrive),
      ).called(2);
    });

    test(
      'runs concorrentes mantem caches independentes (clear de um nao '
      'derruba o do outro)',
      () async {
        when(
          () => validationService.isFeatureAllowed(any()),
        ).thenAnswer((_) async => const rd.Success(true));

        final dest = BackupDestination(
          id: 'd1',
          name: 'GD',
          type: DestinationType.googleDrive,
          config: '{}',
        );

        // Run A inicia, popula cache de A.
        policyService.setRunContext('run-A');
        await policyService.validateDestinationCapabilities(dest);

        // Run B inicia em paralelo (mesmo service singleton). Antes do
        // refactor, este `setRunContext` zerava o cache global do run A
        // — verificamos que isso NÃO acontece mais.
        policyService.setRunContext('run-B');
        await policyService.validateDestinationCapabilities(dest);

        // Run B termina.
        policyService.clearRunContext();

        // Re-ativa run A — cache dele foi preservado (putIfAbsent),
        // então a próxima validação deve ser CACHE HIT.
        policyService.setRunContext('run-A');
        await policyService.validateDestinationCapabilities(dest);

        // Total: 2 chamadas (uma por runId distinto).
        // A 3ª validação (re-ativação de A) deveria pegar do cache.
        verify(
          () => validationService.isFeatureAllowed(LicenseFeatures.googleDrive),
        ).called(2);
      },
    );

    test('clearRunContext nao remove cache de outro runId ativo', () async {
      when(
        () => validationService.isFeatureAllowed(any()),
      ).thenAnswer((_) async => const rd.Success(true));

      final dest = BackupDestination(
        id: 'd1',
        name: 'GD',
        type: DestinationType.googleDrive,
        config: '{}',
      );

      policyService.setRunContext('run-A');
      await policyService.validateDestinationCapabilities(dest);
      policyService.setRunContext('run-B');
      await policyService.validateDestinationCapabilities(dest);
      // clearRunContext() limpa o "atual" (= B) — cache de A intacto.
      policyService.clearRunContext();

      policyService.setRunContext('run-A');
      // 1ª chamada de A deveria ser cache hit (não invoca delegate).
      await policyService.validateDestinationCapabilities(dest);

      // 2 calls: 1 para A inicial, 1 para B. A re-ativação de A é hit.
      verify(
        () => validationService.isFeatureAllowed(LicenseFeatures.googleDrive),
      ).called(2);
    });
  });
}
