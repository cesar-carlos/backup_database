import 'package:drift/drift.dart';

class FileTransfersTable extends Table {
  TextColumn get id => text()();
  TextColumn get scheduleId => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer()();
  IntColumn get currentChunk => integer()();
  IntColumn get totalChunks => integer()();
  TextColumn get status => text()();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get sourcePath => text()();
  TextColumn get destinationPath => text()();
  TextColumn get checksum => text()();

  /// PR-6: rastreabilidade ponta-a-ponta por `runId` de execucao remota.
  /// Permite cliente correlacionar transferencia com `getExecutionStatus`,
  /// logs e historico do servidor. Nullable para preservar compat com
  /// linhas pre-v34 e com fluxos locais (sem `runId`).
  TextColumn get runId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
