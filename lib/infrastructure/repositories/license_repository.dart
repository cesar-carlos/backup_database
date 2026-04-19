import 'dart:convert';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/license.dart';
import 'package:backup_database/domain/repositories/i_license_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class LicenseRepository implements ILicenseRepository {
  LicenseRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<License>> getByDeviceKey(String deviceKey) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar licença',
      action: () async {
        final license = await _database.licenseDao.getByDeviceKey(deviceKey);
        if (license == null) {
          throw const NotFoundFailure(
            message: 'Licença não encontrada para este dispositivo',
          );
        }
        return _toEntity(license);
      },
    );
  }

  @override
  Future<rd.Result<License>> create(License license) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar licença',
      action: () async {
        await _database.licenseDao.insertLicense(_toCompanion(license));
        return license;
      },
    );
  }

  @override
  Future<rd.Result<License>> upsertByDeviceKey(License license) async {
    final preCheck = await RepositoryGuard.run<License>(
      errorMessage: 'Erro ao upsert licença',
      // Sentinela: usamos `_UpsertResult` para sinalizar qual operação
      // o caller deve disparar (insert vs update) sem precisar de
      // múltiplos retornos.
      action: () async {
        final existing = await _database.licenseDao.getByDeviceKey(
          license.deviceKey,
        );
        if (existing != null) {
          throw _UpsertNeedsUpdate(
            license.copyWith(
              id: existing.id,
              createdAt: existing.createdAt,
            ),
          );
        }
        return license;
      },
    );

    return preCheck.fold(
      // Caso "criar": não havia existing.
      create,
      (failure) {
        final original =
            failure is DatabaseFailure ? failure.originalError : null;
        if (original is _UpsertNeedsUpdate) {
          return update(original.licenseToUpdate);
        }
        return Future.value(rd.Failure(failure));
      },
    );
  }

  @override
  Future<rd.Result<License>> update(License license) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar licença',
      action: () async {
        final updated = await _database.licenseDao.updateLicense(
          _toCompanion(license),
        );
        if (!updated) {
          throw const NotFoundFailure(message: 'Licença não encontrada');
        }
        return license;
      },
    );
  }

  @override
  Future<rd.Result<void>> delete(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar licença',
      action: () => _database.licenseDao.deleteLicense(id),
    );
  }

  @override
  Future<rd.Result<List<License>>> getAll() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar licenças',
      action: () async {
        final licenses = await _database.licenseDao.getAll();
        return licenses.map(_toEntity).toList();
      },
    );
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

/// Sentinel para o `upsertByDeviceKey`: sinaliza que a licença deve ir
/// para `update()` em vez de `create()`. Carrega a licença já com `id` e
/// `createdAt` atualizados a partir do registro existente.
class _UpsertNeedsUpdate implements Exception {
  const _UpsertNeedsUpdate(this.licenseToUpdate);
  final License licenseToUpdate;

  @override
  String toString() => 'License needs update via existing row';
}
