import 'dart:async';

import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:dio/dio.dart';

class DioUploadCancellation {
  DioUploadCancellation(bool Function()? isCancelled) {
    if (isCancelled != null) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (isCancelled()) {
          token.cancel(const UploadCancelledException());
          _timer?.cancel();
        }
      });
    }
  }

  final CancelToken token = CancelToken();
  Timer? _timer;

  void dispose() => _timer?.cancel();
}
