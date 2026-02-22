import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/file_transfers_table.dart';
import 'package:drift/drift.dart';

part 'file_transfer_dao.g.dart';

@DriftAccessor(tables: [FileTransfersTable])
class FileTransferDao extends DatabaseAccessor<AppDatabase>
    with _$FileTransferDaoMixin {
  FileTransferDao(super.db);

  Future<List<FileTransfersTableData>> getAll() =>
      select(fileTransfersTable).get();

  Future<FileTransfersTableData?> getById(String id) => (select(
    fileTransfersTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertTransfer(FileTransfersTableCompanion transfer) =>
      into(fileTransfersTable).insert(transfer);

  Future<bool> updateTransfer(FileTransfersTableCompanion transfer) =>
      update(fileTransfersTable).replace(transfer);

  Future<int> deleteTransfer(String id) =>
      (delete(fileTransfersTable)..where((t) => t.id.equals(id))).go();

  Future<List<FileTransfersTableData>> getBySchedule(String scheduleId) =>
      (select(
        fileTransfersTable,
      )..where((t) => t.scheduleId.equals(scheduleId))).get();

  Future<List<FileTransfersTableData>> getCompletedTransfers() => (select(
    fileTransfersTable,
  )..where((t) => t.status.equals('completed'))).get();

  Future<List<FileTransfersTableData>> getFailedTransfers() => (select(
    fileTransfersTable,
  )..where((t) => t.status.equals('failed'))).get();

  Future<int> updateProgress(String id, int currentChunk) {
    return (update(fileTransfersTable)..where((t) => t.id.equals(id))).write(
      FileTransfersTableCompanion(
        currentChunk: Value(currentChunk),
      ),
    );
  }

  Future<int> updateStatus(
    String id,
    String status, {
    String? errorMessage,
  }) {
    return (update(fileTransfersTable)..where((t) => t.id.equals(id))).write(
      FileTransfersTableCompanion(
        status: Value(status),
        errorMessage: Value(errorMessage),
        completedAt: status == 'completed' || status == 'failed'
            ? Value(DateTime.now())
            : const Value.absent(),
      ),
    );
  }

  Stream<List<FileTransfersTableData>> watchAll() =>
      select(fileTransfersTable).watch();
}
