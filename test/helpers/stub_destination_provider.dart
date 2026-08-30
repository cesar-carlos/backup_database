import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../unit/helpers/mock_repositories.dart';

DestinationProvider stubDestinationProvider() {
  final repository = MockBackupDestinationRepository();
  final scheduleRepository = MockScheduleRepository();
  final licensePolicy = MockLicensePolicyService();

  when(repository.getAll).thenAnswer(
    (_) async => const rd.Success(<BackupDestination>[]),
  );

  return DestinationProvider(
    repository,
    scheduleRepository,
    licensePolicy,
  );
}
