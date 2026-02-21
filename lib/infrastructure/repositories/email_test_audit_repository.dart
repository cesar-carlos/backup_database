import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class EmailTestAuditRepository implements IEmailTestAuditRepository {
  EmailTestAuditRepository(this._database);

  final AppDatabase _database;

  @override
  Future<rd.Result<EmailTestAudit>> create(EmailTestAudit audit) async {
    try {
      await _database.emailTestAuditDao.insertAudit(_toCompanion(audit));
      return rd.Success(audit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao salvar auditoria de teste SMTP: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<List<EmailTestAudit>>> getRecent({
    String? configId,
    DateTime? startAt,
    DateTime? endAt,
    int limit = 100,
  }) async {
    try {
      final rows = await _database.emailTestAuditDao.getRecent(
        configId: configId,
        startAt: startAt,
        endAt: endAt,
        limit: limit,
      );
      return rd.Success(rows.map(_toEntity).toList());
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao consultar auditoria de teste SMTP: $e',
        ),
      );
    }
  }

  EmailTestAudit _toEntity(EmailTestAuditTableData data) {
    return EmailTestAudit(
      id: data.id,
      configId: data.configId,
      correlationId: data.correlationId,
      recipientEmail: data.recipientEmail,
      senderEmail: data.senderEmail,
      smtpServer: data.smtpServer,
      smtpPort: data.smtpPort,
      status: data.status,
      errorType: data.errorType,
      errorMessage: data.errorMessage,
      attempts: data.attempts,
      createdAt: data.createdAt,
    );
  }

  EmailTestAuditTableCompanion _toCompanion(EmailTestAudit audit) {
    return EmailTestAuditTableCompanion(
      id: Value(audit.id),
      configId: Value(audit.configId),
      correlationId: Value(audit.correlationId),
      recipientEmail: Value(audit.recipientEmail),
      senderEmail: Value(audit.senderEmail),
      smtpServer: Value(audit.smtpServer),
      smtpPort: Value(audit.smtpPort),
      status: Value(audit.status),
      errorType: Value(audit.errorType),
      errorMessage: Value(audit.errorMessage),
      attempts: Value(audit.attempts),
      createdAt: Value(audit.createdAt),
    );
  }
}
