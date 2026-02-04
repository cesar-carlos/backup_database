import 'package:backup_database/domain/entities/disk_space_info.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:result_dart/result_dart.dart' as rd;

class CheckDiskSpace {
  CheckDiskSpace(this._storageChecker);
  final IStorageChecker _storageChecker;

  Future<rd.Result<DiskSpaceInfo>> call(String path) async {
    return _storageChecker.checkSpace(path);
  }
}
