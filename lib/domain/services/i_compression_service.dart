import 'package:result_dart/result_dart.dart';

import 'compression_result.dart';

abstract class ICompressionService {
  Future<Result<CompressionResult>> compress({
    required String path,
    String? outputPath,
    bool deleteOriginal,
  });
}

