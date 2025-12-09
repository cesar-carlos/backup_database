import 'package:flutter/foundation.dart';

import '../../domain/entities/backup_destination.dart';
import '../../domain/repositories/i_backup_destination_repository.dart';
import '../../domain/repositories/i_schedule_repository.dart';

class DestinationProvider extends ChangeNotifier {
  final IBackupDestinationRepository _repository;
  final IScheduleRepository _scheduleRepository;

  DestinationProvider(
    this._repository,
    this._scheduleRepository,
  ) {
    loadDestinations();
  }

  List<BackupDestination> _destinations = [];
  bool _isLoading = false;
  String? _error;

  List<BackupDestination> get destinations => _destinations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadDestinations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repository.getAll();

    result.fold(
      (destinations) {
        _destinations = destinations;
        _isLoading = false;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
      },
    );

    notifyListeners();
  }

  Future<bool> createDestination(BackupDestination destination) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repository.create(destination);

    return result.fold(
      (created) {
        _destinations.add(created);
        _isLoading = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> updateDestination(BackupDestination destination) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repository.update(destination);

    return result.fold(
      (updated) {
        final index = _destinations.indexWhere((d) => d.id == updated.id);
        if (index != -1) {
          _destinations[index] = updated;
        }
        _isLoading = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> deleteDestination(String id) async {
    // Bloqueia exclusão se houver agendamentos usando este destino
    final schedulesResult = await _scheduleRepository.getAll();
    final hasLinked = schedulesResult.isSuccess() &&
        schedulesResult.getOrNull()!
            .any((s) => s.destinationIds.contains(id));
    if (hasLinked) {
      _error =
          'Há agendamentos vinculados a este destino. Remova-os antes de excluir.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repository.delete(id);

    return result.fold(
      (_) {
        _destinations.removeWhere((d) => d.id == id);
        _isLoading = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> toggleEnabled(String id, bool enabled) async {
    final destination = _destinations.firstWhere((d) => d.id == id);
    final updated = destination.copyWith(enabled: enabled);
    return updateDestination(updated);
  }
}

