import 'package:result_dart/result_dart.dart';

import '../entities/compression_format.dart';
import 'compression_result.dart';

abstract class ICompressionService {
  Future<Result<CompressionResult>> compress({
    required String path,
    String? outputPath,
    bool deleteOriginal,
    CompressionFormat? format,
  });
}

