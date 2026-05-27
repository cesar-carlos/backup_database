import 'package:drift/drift.dart';

/// PR-6: persistencia do audit log de comandos mutaveis no socket
/// servidor. Espelha `SocketMutableCommandAuditEntry` em
/// `socket_server_telemetry.dart`. Retencao default 30 dias
/// (configuravel em `BackupConstants.auditRetentionPeriod`).
class MutableCommandAuditTable extends Table {
  TextColumn get id => text()();
  TextColumn get clientId => text()();
  TextColumn get commandType => text()();
  IntColumn get requestId => integer().nullable()();
  TextColumn get runId => text().nullable()();
  TextColumn get idempotencyKey => text().nullable()();
  TextColumn get result => text()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get timestampUtcMicros => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
