import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/services/compression_result.dart';
import 'package:result_dart/result_dart.dart';

abstract class ICompressionService {
  Future<Result<CompressionResult>> compress({
    required String path,
    String? outputPath,
    bool deleteOriginal,
    CompressionFormat? format,
  });
}
