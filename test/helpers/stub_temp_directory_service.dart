import 'dart:io';

import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockMachineSettingsRepository extends Mock
    implements IMachineSettingsRepository {}

/// [TempDirectoryService] de teste com permissão de escrita configurável.
class StubTempDirectoryService extends TempDirectoryService {
  StubTempDirectoryService({
    IMachineSettingsRepository? machineSettings,
    this.allowWrite = true,
  }) : super(
         machineSettings:
             machineSettings ?? MockMachineSettingsRepository(),
       );

  final bool allowWrite;

  @override
  Future<bool> validateDownloadsDirectory() async => allowWrite;

  @override
  Future<Directory> getDownloadsDirectory() async =>
      Directory.systemTemp.createTempSync('backup_db_test_');
}
