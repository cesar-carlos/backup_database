import 'package:result_dart/result_dart.dart' as rd;

abstract class IDeviceKeyService {
  Future<rd.Result<String>> getDeviceKey();
}

