import 'package:backup_database/core/utils/unit.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class ISecureCredentialService {
  Future<rd.Result<Unit>> storePassword({
    required String key,
    required String password,
  });

  Future<rd.Result<String>> getPassword({
    required String key,
  });

  Future<rd.Result<Unit>> deletePassword({
    required String key,
  });

  Future<rd.Result<Unit>> storeToken({
    required String key,
    required Map<String, dynamic> tokenData,
  });

  Future<rd.Result<Map<String, dynamic>>> getToken({
    required String key,
  });

  Future<rd.Result<Unit>> deleteToken({
    required String key,
  });

  Future<rd.Result<bool>> containsKey({
    required String key,
  });

  Future<rd.Result<Unit>> deleteAll();

  Future<rd.Result<Map<String, String>>> readAll();
}
