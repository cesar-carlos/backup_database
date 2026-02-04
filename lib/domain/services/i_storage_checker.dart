import 'package:backup_database/domain/entities/disk_space_info.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IStorageChecker {
  Future<rd.Result<DiskSpaceInfo>> checkSpace(String path);
}
