import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:result_dart/result_dart.dart' as rd;

class DeleteSchedule {
  DeleteSchedule(this._repository);
  final IScheduleRepository _repository;

  Future<rd.Result<void>> call(String id) async {
    if (id.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'ID não pode ser vazio'),
      );
    }

    return _repository.delete(id);
  }
}
