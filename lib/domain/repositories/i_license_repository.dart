import 'package:result_dart/result_dart.dart' as rd;

import '../entities/license.dart';

abstract class ILicenseRepository {
  Future<rd.Result<License>> getByDeviceKey(String deviceKey);
  Future<rd.Result<License>> create(License license);
  Future<rd.Result<License>> update(License license);
  Future<rd.Result<void>> delete(String id);
  Future<rd.Result<List<License>>> getAll();
}

