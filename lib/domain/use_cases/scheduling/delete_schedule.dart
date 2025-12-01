import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../repositories/repositories.dart';

class DeleteSchedule {
  final IScheduleRepository _repository;

  DeleteSchedule(this._repository);

  Future<rd.Result<void>> call(String id) async {
    if (id.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'ID não pode ser vazio'),
      );
    }

    return await _repository.delete(id);
  }
}

