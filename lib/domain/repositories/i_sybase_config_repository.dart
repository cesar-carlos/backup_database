import '../entities/sybase_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class ISybaseConfigRepository {
  Future<rd.Result<List<SybaseConfig>>> getAll();
  Future<rd.Result<SybaseConfig>> getById(String id);
  Future<rd.Result<SybaseConfig>> create(SybaseConfig config);
  Future<rd.Result<SybaseConfig>> update(SybaseConfig config);
  Future<rd.Result<void>> delete(String id);
  Future<rd.Result<List<SybaseConfig>>> getEnabled();
}

