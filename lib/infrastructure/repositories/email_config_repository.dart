import 'dart:convert';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class EmailConfigRepository implements IEmailConfigRepository {
  EmailConfigRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<EmailConfig>>> getAll() async {
    try {
      final configs = await _database.emailConfigDao.getAll();
      return rd.Success(configs.map(_toEntity).toList());
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar lista de configuracoes de e-mail: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<EmailConfig>> getById(String id) async {
    try {
      final config = await _database.emailConfigDao.getById(id);
      if (config == null) {
        return const rd.Failure(
          NotFoundFailure(message: 'Configuracao de e-mail nao encontrada'),
        );
      }
      return rd.Success(_toEntity(config));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configuracao de e-mail: $e'),
      );
    }
  }

  @override
  Future<rd.Result<EmailConfig>> create(EmailConfig config) async {
    try {
      await _database.emailConfigDao.insertConfig(_toCompanion(config));
      return rd.Success(config);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao criar configuracao de e-mail',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao criar configuracao de e-mail: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<EmailConfig>> update(EmailConfig config) async {
    try {
      final updated = await _database.emailConfigDao.updateConfig(
        _toCompanion(config),
      );

      if (!updated) {
        return const rd.Failure(
          NotFoundFailure(message: 'Configuracao de e-mail nao encontrada'),
        );
      }

      return rd.Success(config);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao atualizar configuracao de e-mail',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao atualizar configuracao de e-mail: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> deleteById(String id) async {
    try {
      await _database.emailConfigDao.deleteById(id);
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar configuracao de e-mail: $e'),
      );
    }
  }

  @override
  Future<rd.Result<EmailConfig>> get() async {
    try {
      final configs = await _database.emailConfigDao.getAll();
      if (configs.isEmpty) {
        return const rd.Failure(
          NotFoundFailure(message: 'Configuracao de e-mail nao encontrada'),
        );
      }
      return rd.Success(_toEntity(configs.first));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar configuracao de e-mail: $e'),
      );
    }
  }

  @override
  Future<rd.Result<EmailConfig>> save(EmailConfig config) async {
    try {
      final existing = await _database.emailConfigDao.getById(config.id);
      if (existing == null) {
        return create(config);
      }
      return update(config);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao salvar configuracao de e-mail',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao salvar configuracao de e-mail: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete() async {
    try {
      await _database.emailConfigDao.deleteAll();
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar configuracoes de e-mail: $e'),
      );
    }
  }

  EmailConfig _toEntity(EmailConfigsTableData data) {
    List<String> recipients;
    try {
      recipients = (jsonDecode(data.recipients) as List).cast<String>();
    } on Object catch (e) {
      LoggerService.warning(
        '[EmailConfigRepository] Erro ao decodificar recipients para config ${data.id}: $e',
      );
      recipients = [];
    }

    return EmailConfig(
      id: data.id,
      configName: data.configName,
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
      configName: Value(config.configName),
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
