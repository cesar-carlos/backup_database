import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class ILicensePolicyService {
  Future<rd.Result<void>> validateScheduleCapabilities(Schedule schedule);

  Future<rd.Result<void>> validateDestinationCapabilities(
    BackupDestination destination,
  );

  Future<rd.Result<void>> validateExecutionCapabilities(
    Schedule schedule,
    List<BackupDestination> destinations,
  );

  void setRunContext(String? runId);

  void clearRunContext();
}
