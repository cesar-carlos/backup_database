import 'package:backup_database/application/providers/async_state_mixin.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:flutter/foundation.dart';

class DestinationProvider extends ChangeNotifier with AsyncStateMixin {
  DestinationProvider(
    this._repository,
    this._scheduleRepository,
    this._licensePolicyService,
  ) {
    loadDestinations();
  }
  final IBackupDestinationRepository _repository;
  final IScheduleRepository _scheduleRepository;
  final ILicensePolicyService _licensePolicyService;

  List<BackupDestination> _destinations = [];

  List<BackupDestination> get destinations => _destinations;

  Future<void> loadDestinations() async {
    await runAsync<void>(
      genericErrorMessage: 'Erro ao carregar destinos',
      action: () async {
        final result = await _repository.getAll();
        result.fold(
          (destinations) => _destinations = destinations,
          (failure) => throw failure,
        );
      },
    );
  }

  Future<bool> createDestination(BackupDestination destination) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao criar destino',
      action: () async {
        await _validateLicenseOrThrow(destination);
        final result = await _repository.create(destination);
        return result.fold(
          (created) {
            // P9 fix: reassign em vez de `_destinations.add(...)` para
            // que listeners que comparam por `identical()` detectem.
            _destinations = [..._destinations, created];
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> updateDestination(BackupDestination destination) async {
    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao atualizar destino',
      action: () async {
        await _validateLicenseOrThrow(destination);
        final result = await _repository.update(destination);
        return result.fold(
          (updated) {
            _destinations = _destinations
                .map((d) => d.id == updated.id ? updated : d)
                .toList();
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> deleteDestination(String id) async {
    // Pre-checagens sincronas (não precisam do contador de loading).
    final schedulesResult = await _scheduleRepository.getByDestinationId(id);
    if (schedulesResult.isError()) {
      final failure = schedulesResult.exceptionOrNull();
      setErrorManual(
        failure is Failure
            ? 'Nao foi possivel validar dependencias: ${failure.message}'
            : 'Nao foi possivel validar dependencias antes da exclusao.',
      );
      return false;
    }

    final hasLinked = (schedulesResult.getOrNull() ?? []).isNotEmpty;
    if (hasLinked) {
      setErrorManual(
        'Ha agendamentos vinculados a este destino. '
        'Remova-os antes de excluir.',
      );
      return false;
    }

    final ok = await runAsync<bool>(
      genericErrorMessage: 'Erro ao deletar destino',
      action: () async {
        final result = await _repository.delete(id);
        return result.fold(
          (_) {
            _destinations =
                _destinations.where((d) => d.id != id).toList();
            return true;
          },
          (failure) => throw failure,
        );
      },
    );
    return ok ?? false;
  }

  Future<bool> duplicateDestination(BackupDestination source) async {
    final copy = BackupDestination(
      name: '${source.name} (cópia)',
      type: source.type,
      config: source.config,
      enabled: source.enabled,
    );
    return createDestination(copy);
  }

  Future<bool> toggleEnabled(String id, bool enabled) async {
    final destination = getDestinationById(id);
    if (destination == null) {
      setErrorManual('Destino não encontrado.');
      return false;
    }
    return updateDestination(destination.copyWith(enabled: enabled));
  }

  /// P6 fix: lookup direto sem `try/firstWhere`.
  BackupDestination? getDestinationById(String id) {
    for (final d in _destinations) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _validateLicenseOrThrow(BackupDestination destination) async {
    final policyResult = await _licensePolicyService
        .validateDestinationCapabilities(destination);
    if (policyResult.isError()) {
      throw policyResult.exceptionOrNull()!;
    }
  }
}
