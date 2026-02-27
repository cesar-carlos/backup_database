import 'dart:convert';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/repositories/i_license_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LicenseRepository implements ILicenseRepository {
  LicenseRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<License>> getByDeviceKey(String deviceKey) async {
    try {
      final license = await _database.licenseDao.getByDeviceKey(deviceKey);
      if (license == null) {
        return const rd.Failure(
          NotFoundFailure(
            message: 'Licença não encontrada para este dispositivo',
          ),
        );
      }
      return rd.Success(_toEntity(license));
    } on Object catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar licença: $e'));
    }
  }

  @override
  Future<rd.Result<License>> create(License license) async {
    try {
      final companion = _toCompanion(license);
      await _database.licenseDao.insertLicense(companion);
      return rd.Success(license);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao criar licença', e, stackTrace);
      return rd.Failure(DatabaseFailure(message: 'Erro ao criar licença: $e'));
    }
  }

  @override
  Future<rd.Result<License>> upsertByDeviceKey(License license) async {
    try {
      final existing = await _database.licenseDao.getByDeviceKey(license.deviceKey);
      if (existing != null) {
        final updated = license.copyWith(
          id: existing.id,
          createdAt: existing.createdAt,
        );
        return update(updated);
      }
      return create(license);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao upsert licença por deviceKey', e, stackTrace);
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao upsert licença: $e'),
      );
    }
  }

  @override
  Future<rd.Result<License>> update(License license) async {
    try {
      final companion = _toCompanion(license);
      final updated = await _database.licenseDao.updateLicense(companion);
      if (!updated) {
        return const rd.Failure(
          NotFoundFailure(message: 'Licença não encontrada'),
        );
      }
      return rd.Success(license);
    } on Object catch (e, stackTrace) {
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
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar licença: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<License>>> getAll() async {
    try {
      final licenses = await _database.licenseDao.getAll();
      final entities = licenses.map(_toEntity).toList();
      return rd.Success(entities);
    } on Object catch (e) {
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
    } on Object catch (e) {
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
