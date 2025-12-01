import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../core/core.dart';
import '../../domain/entities/email_config.dart';
import '../../domain/repositories/i_email_config_repository.dart';
import '../datasources/local/database.dart';

class EmailConfigRepository implements IEmailConfigRepository {
  final AppDatabase _database;

  EmailConfigRepository(this._database);

  @override
  Future<rd.Result<EmailConfig>> get() async {
    try {
      final config = await _database.emailConfigDao.get();
      if (config == null) {
        return rd.Failure(
          NotFoundFailure(message: 'Configuração de e-mail não encontrada'),
        );
      }
      return rd.Success(_toEntity(config));
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configuração de e-mail: $e'),
      );
    }
  }

  @override
  Future<rd.Result<EmailConfig>> save(EmailConfig config) async {
    try {
      final existing = await _database.emailConfigDao.get();
      final companion = _toCompanion(config);

      if (existing == null) {
        await _database.emailConfigDao.insertConfig(companion);
      } else {
        await _database.emailConfigDao.updateConfig(companion);
      }

      return rd.Success(config);
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao salvar configuração de e-mail',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao salvar configuração de e-mail: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete() async {
    try {
      await _database.emailConfigDao.deleteAll();
      return const rd.Success(unit);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar configuração de e-mail: $e'),
      );
    }
  }

  EmailConfig _toEntity(EmailConfigsTableData data) {
    List<String> recipients;
    try {
      recipients = (jsonDecode(data.recipients) as List).cast<String>();
    } catch (e) {
      LoggerService.warning(
        '[EmailConfigRepository] Erro ao decodificar recipients para config ${data.id}: $e',
      );
      recipients = [];
    }

    return EmailConfig(
      id: data.id,
      senderName: data.senderName,
      fromEmail: data.fromEmail,
      fromName: data.fromName,
      smtpServer: data.smtpServer,
      smtpPort: data.smtpPort,
      username: data.username,
      password: data.password,
      useSsl: data.useSsl,
      recipients: recipients,
      notifyOnSuccess: data.notifyOnSuccess,
      notifyOnError: data.notifyOnError,
      notifyOnWarning: data.notifyOnWarning,
      attachLog: data.attachLog,
      enabled: data.enabled,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  EmailConfigsTableCompanion _toCompanion(EmailConfig config) {
    return EmailConfigsTableCompanion(
      id: Value(config.id),
      senderName: Value(config.senderName),
      fromEmail: Value(config.fromEmail),
      fromName: Value(config.fromName),
      smtpServer: Value(config.smtpServer),
      smtpPort: Value(config.smtpPort),
      username: Value(config.username),
      password: Value(config.password),
      useSsl: Value(config.useSsl),
      recipients: Value(jsonEncode(config.recipients)),
      notifyOnSuccess: Value(config.notifyOnSuccess),
      notifyOnError: Value(config.notifyOnError),
      notifyOnWarning: Value(config.notifyOnWarning),
      attachLog: Value(config.attachLog),
      enabled: Value(config.enabled),
      createdAt: Value(config.createdAt),
      updatedAt: Value(config.updatedAt),
    );
  }
}
