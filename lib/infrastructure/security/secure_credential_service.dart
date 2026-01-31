import 'dart:convert';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SecureCredentialService implements ISecureCredentialService {
  SecureCredentialService({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<rd.Result<Unit>> storePassword({
    required String key,
    required String password,
  }) async {
    try {
      await _storage.write(key: key, value: password);
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to store password for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao armazenar credencial: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<String>> getPassword({
    required String key,
  }) async {
    try {
      final password = await _storage.read(key: key);
      if (password == null) {
        return rd.Failure(
          StorageFailure(
            message: 'Credencial não encontrada: $key',
          ),
        );
      }
      return rd.Success(password);
    } on Object catch (e, s) {
      LoggerService.error('Failed to read password for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao ler credencial: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Unit>> deletePassword({
    required String key,
  }) async {
    try {
      await _storage.delete(key: key);
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to delete password for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao deletar credencial: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Unit>> storeToken({
    required String key,
    required Map<String, dynamic> tokenData,
  }) async {
    try {
      final jsonToken = jsonEncode(tokenData);
      await _storage.write(key: key, value: jsonToken);
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to store token for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao armazenar token: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Map<String, dynamic>>> getToken({
    required String key,
  }) async {
    try {
      final jsonToken = await _storage.read(key: key);
      if (jsonToken == null) {
        return rd.Failure(
          StorageFailure(
            message: 'Token não encontrado: $key',
          ),
        );
      }

      final tokenData = jsonDecode(jsonToken) as Map<String, dynamic>;
      return rd.Success(tokenData);
    } on Object catch (e, s) {
      LoggerService.error('Failed to read token for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao ler token: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Unit>> deleteToken({
    required String key,
  }) async {
    try {
      await _storage.delete(key: key);
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to delete token for key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao deletar token: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<bool>> containsKey({
    required String key,
  }) async {
    try {
      final contains = await _storage.containsKey(key: key);
      return rd.Success(contains);
    } on Object catch (e, s) {
      LoggerService.error('Failed to check key: $key', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao verificar chave: $key',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Unit>> deleteAll() async {
    try {
      await _storage.deleteAll();
      return const rd.Success(unit);
    } on Object catch (e, s) {
      LoggerService.error('Failed to delete all credentials', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao deletar todas as credenciais',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<Map<String, String>>> readAll() async {
    try {
      final allData = await _storage.readAll();
      return rd.Success(allData);
    } on Object catch (e, s) {
      LoggerService.error('Failed to read all credentials', e, s);
      return rd.Failure(
        StorageFailure(
          message: 'Falha ao ler todas as credenciais',
          originalError: e,
        ),
      );
    }
  }
}
