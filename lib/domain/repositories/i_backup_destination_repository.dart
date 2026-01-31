import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IBackupDestinationRepository {
  Future<rd.Result<List<BackupDestination>>> getAll();
  Future<rd.Result<BackupDestination>> getById(String id);
  Future<rd.Result<BackupDestination>> create(BackupDestination destination);
  Future<rd.Result<BackupDestination>> update(BackupDestination destination);
  Future<rd.Result<void>> delete(String id);
  Future<rd.Result<List<BackupDestination>>> getByType(DestinationType type);
  Future<rd.Result<List<BackupDestination>>> getEnabled();
}
