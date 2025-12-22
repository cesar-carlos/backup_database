import 'package:result_dart/result_dart.dart';

import '../entities/schedule.dart';
import '../entities/sql_server_config.dart';
import '../entities/sybase_config.dart';

abstract class ISqlScriptExecutionService {
  Future<Result<void>> executeScript({
    required DatabaseType databaseType,
    required SqlServerConfig? sqlServerConfig,
    required SybaseConfig? sybaseConfig,
    required String script,
  });
}

