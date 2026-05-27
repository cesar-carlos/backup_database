import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/mutable_command_audit_table.dart';
import 'package:drift/drift.dart';

part 'mutable_command_audit_dao.g.dart';

/// PR-6: DAO da persistencia de audit log para `SocketServerTelemetry`.
///
/// Operacoes:
/// - [insertAudit]: persiste uma entrada (best-effort).
/// - [deleteOlderThan]: usado pelo job de retencao 30 dias.
/// - [recentAudits]: leitura paginada para tooling/UI/suporte.
@DriftAccessor(tables: [MutableCommandAuditTable])
class MutableCommandAuditDao extends DatabaseAccessor<AppDatabase>
    with _$MutableCommandAuditDaoMixin {
  MutableCommandAuditDao(super.db);

  Future<void> insertAudit({
    required String id,
    required String clientId,
    required String commandType,
    required String result,
    required DateTime timestampUtc,
    int? requestId,
    String? runId,
    String? idempotencyKey,
    int? durationMs,
  }) async {
    await into(mutableCommandAuditTable).insert(
      MutableCommandAuditTableCompanion.insert(
        id: id,
        clientId: clientId,
        commandType: commandType,
        requestId: Value(requestId),
        runId: Value(runId),
        idempotencyKey: Value(idempotencyKey),
        result: result,
        durationMs: Value(durationMs),
        timestampUtcMicros: timestampUtc.toUtc().microsecondsSinceEpoch,
      ),
    );
  }

  Future<int> deleteOlderThan(DateTime cutoffUtc) {
    final cutoffMicros = cutoffUtc.toUtc().microsecondsSinceEpoch;
    return (delete(mutableCommandAuditTable)
          ..where((t) => t.timestampUtcMicros.isSmallerThanValue(cutoffMicros)))
        .go();
  }

  /// Leitura defensiva: ordena por timestamp desc, limita por seguranca.
  Future<List<MutableCommandAuditTableData>> recentAudits({
    int limit = 100,
  }) {
    return (select(mutableCommandAuditTable)
          ..orderBy([(t) => OrderingTerm.desc(t.timestampUtcMicros)])
          ..limit(limit))
        .get();
  }

  Future<int> countRows() async {
    final q = selectOnly(mutableCommandAuditTable)
      ..addColumns([mutableCommandAuditTable.id.count()]);
    final row = await q.getSingle();
    return row.read(mutableCommandAuditTable.id.count()) ?? 0;
  }
}
