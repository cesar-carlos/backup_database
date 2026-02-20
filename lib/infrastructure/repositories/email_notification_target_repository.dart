import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class EmailNotificationTargetRepository
    implements IEmailNotificationTargetRepository {
  EmailNotificationTargetRepository(this._database);

  final AppDatabase _database;

  @override
  Future<rd.Result<List<EmailNotificationTarget>>> getByConfigId(
    String emailConfigId,
  ) async {
    try {
      final targets = await _database.emailNotificationTargetDao.getByConfigId(
        emailConfigId,
      );
      return rd.Success(targets.map(_toEntity).toList());
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar destinatarios da configuracao: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<EmailNotificationTarget>> getById(String id) async {
    try {
      final target = await _database.emailNotificationTargetDao.getById(id);
      if (target == null) {
        return const rd.Failure(
          NotFoundFailure(
            message: 'Destinatario de notificacao nao encontrado',
          ),
        );
      }
      return rd.Success(_toEntity(target));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar destinatario de notificacao: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<EmailNotificationTarget>> create(
    EmailNotificationTarget target,
  ) async {
    try {
      await _database.emailNotificationTargetDao.insertTarget(
        _toCompanion(target),
      );
      return rd.Success(target);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao criar destinatario de notificacao',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao criar destinatario de notificacao: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<EmailNotificationTarget>> update(
    EmailNotificationTarget target,
  ) async {
    try {
      final updated = await _database.emailNotificationTargetDao.updateTarget(
        _toCompanion(target),
      );
      if (!updated) {
        return const rd.Failure(
          NotFoundFailure(
            message: 'Destinatario de notificacao nao encontrado',
          ),
        );
      }
      return rd.Success(target);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao atualizar destinatario de notificacao',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao atualizar destinatario de notificacao: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> deleteById(String id) async {
    try {
      await _database.emailNotificationTargetDao.deleteById(id);
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao remover destinatario de notificacao: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> deleteByConfigId(String emailConfigId) async {
    try {
      await _database.emailNotificationTargetDao.deleteByConfigId(
        emailConfigId,
      );
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao remover destinatarios da configuracao: $e',
        ),
      );
    }
  }

  EmailNotificationTarget _toEntity(EmailNotificationTargetsTableData data) {
    return EmailNotificationTarget(
      id: data.id,
      emailConfigId: data.emailConfigId,
      recipientEmail: data.recipientEmail,
      notifyOnSuccess: data.notifyOnSuccess,
      notifyOnError: data.notifyOnError,
      notifyOnWarning: data.notifyOnWarning,
      enabled: data.enabled,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  EmailNotificationTargetsTableCompanion _toCompanion(
    EmailNotificationTarget target,
  ) {
    return EmailNotificationTargetsTableCompanion(
      id: Value(target.id),
      emailConfigId: Value(target.emailConfigId),
      recipientEmail: Value(target.recipientEmail),
      notifyOnSuccess: Value(target.notifyOnSuccess),
      notifyOnError: Value(target.notifyOnError),
      notifyOnWarning: Value(target.notifyOnWarning),
      enabled: Value(target.enabled),
      createdAt: Value(target.createdAt),
      updatedAt: Value(target.updatedAt),
    );
  }
}
