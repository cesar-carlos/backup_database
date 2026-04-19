import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class EmailNotificationTargetRepository
    implements IEmailNotificationTargetRepository {
  EmailNotificationTargetRepository(this._database);

  final AppDatabase _database;

  @override
  Future<rd.Result<List<EmailNotificationTarget>>> getByConfigId(
    String emailConfigId,
  ) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar destinatarios da configuracao',
      action: () async {
        final targets = await _database.emailNotificationTargetDao
            .getByConfigId(emailConfigId);
        return targets.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<EmailNotificationTarget>> getById(String id) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar destinatario de notificacao',
      action: () async {
        final target = await _database.emailNotificationTargetDao.getById(id);
        if (target == null) {
          throw const NotFoundFailure(
            message: 'Destinatario de notificacao nao encontrado',
          );
        }
        return _toEntity(target);
      },
    );
  }

  @override
  Future<rd.Result<EmailNotificationTarget>> create(
    EmailNotificationTarget target,
  ) {
    final normalizedTarget = _normalizeTarget(target);
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar destinatario de notificacao',
      action: () async {
        await _database.emailNotificationTargetDao.insertTarget(
          _toCompanion(normalizedTarget),
        );
        return normalizedTarget;
      },
    );
  }

  @override
  Future<rd.Result<EmailNotificationTarget>> update(
    EmailNotificationTarget target,
  ) {
    final normalizedTarget = _normalizeTarget(target);
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar destinatario de notificacao',
      action: () async {
        final updated = await _database.emailNotificationTargetDao.updateTarget(
          _toCompanion(normalizedTarget),
        );
        if (!updated) {
          throw const NotFoundFailure(
            message: 'Destinatario de notificacao nao encontrado',
          );
        }
        return normalizedTarget;
      },
    );
  }

  @override
  Future<rd.Result<void>> deleteById(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao remover destinatario de notificacao',
      action: () => _database.emailNotificationTargetDao.deleteById(id),
    );
  }

  @override
  Future<rd.Result<void>> deleteByConfigId(String emailConfigId) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao remover destinatarios da configuracao',
      action: () => _database.emailNotificationTargetDao.deleteByConfigId(
        emailConfigId,
      ),
    );
  }

  EmailNotificationTarget _toEntity(EmailNotificationTargetsTableData data) {
    return EmailNotificationTarget(
      id: data.id,
      emailConfigId: data.emailConfigId,
      recipientEmail: data.recipientEmail.trim().toLowerCase(),
      notifyOnSuccess: data.notifyOnSuccess,
      notifyOnError: data.notifyOnError,
      notifyOnWarning: data.notifyOnWarning,
      enabled: data.enabled,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  EmailNotificationTarget _normalizeTarget(EmailNotificationTarget target) {
    return target.copyWith(
      recipientEmail: target.recipientEmail.trim().toLowerCase(),
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
