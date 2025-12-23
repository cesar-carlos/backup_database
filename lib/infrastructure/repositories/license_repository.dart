import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../core/core.dart';
import '../../domain/entities/license.dart';
import '../../domain/repositories/i_license_repository.dart';
import '../datasources/local/database.dart';

class LicenseRepository implements ILicenseRepository {
  final AppDatabase _database;

  LicenseRepository(this._database);

  @override
  Future<rd.Result<License>> getByDeviceKey(String deviceKey) async {
    try {
      final license = await _database.licenseDao.getByDeviceKey(deviceKey);
      if (license == null) {
        return rd.Failure(
          NotFoundFailure(
            message: 'Licença não encontrada para este dispositivo',
          ),
        );
      }
      return rd.Success(_toEntity(license));
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar licença: $e'));
    }
  }

  @override
  Future<rd.Result<License>> create(License license) async {
    try {
      final companion = _toCompanion(license);
      await _database.licenseDao.insertLicense(companion);
      return rd.Success(license);
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao criar licença', e, stackTrace);
      return rd.Failure(DatabaseFailure(message: 'Erro ao criar licença: $e'));
    }
  }

  @override
  Future<rd.Result<License>> update(License license) async {
    try {
      final companion = _toCompanion(license);
      final updated = await _database.licenseDao.updateLicense(companion);
      if (!updated) {
        return rd.Failure(NotFoundFailure(message: 'Licença não encontrada'));
      }
      return rd.Success(license);
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao atualizar licença', e, stackTrace);
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao atualizar licença: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    try {
      await _database.licenseDao.deleteLicense(id);
      return const rd.Success(unit);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar licença: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<License>>> getAll() async {
    try {
      final licenses = await _database.licenseDao.getAll();
      final entities = licenses.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar licenças: $e'),
      );
    }
  }

  License _toEntity(LicensesTableData data) {
    List<String> allowedFeatures;
    try {
      allowedFeatures = (jsonDecode(data.allowedFeatures) as List)
          .cast<String>();
    } catch (e) {
      LoggerService.warning(
        '[LicenseRepository] Erro ao decodificar allowedFeatures para licença ${data.id}: $e',
      );
      allowedFeatures = [];
    }

    return License(
      id: data.id,
      deviceKey: data.deviceKey,
      licenseKey: data.licenseKey,
      expiresAt: data.expiresAt,
      allowedFeatures: allowedFeatures,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  LicensesTableCompanion _toCompanion(License license) {
    return LicensesTableCompanion(
      id: Value(license.id),
      deviceKey: Value(license.deviceKey),
      licenseKey: Value(license.licenseKey),
      expiresAt: Value(license.expiresAt),
      allowedFeatures: Value(jsonEncode(license.allowedFeatures)),
      createdAt: Value(license.createdAt),
      updatedAt: Value(license.updatedAt),
    );
  }
}
