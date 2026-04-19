import 'dart:convert';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class EmailConfigRepository implements IEmailConfigRepository {
  EmailConfigRepository(this._database, this._secureCredentialService);
  final AppDatabase _database;
  final ISecureCredentialService _secureCredentialService;

  static const String _smtpPasswordKeyPrefix = 'email_smtp_password_';
  static const String _smtpOAuthTokenKeyPrefix = 'email_smtp_oauth_token_';

  @override
  Future<rd.Result<List<EmailConfig>>> getAll() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar lista de configuracoes de e-mail',
      action: () async {
        final configs = await _database.emailConfigDao.getAll();
        return Future.wait(configs.map(_toEntity));
      },
    );
  }

  @override
  Future<rd.Result<EmailConfig>> getById(String id) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar configuracao de e-mail',
      action: () async {
        final config = await _database.emailConfigDao.getById(id);
        if (config == null) {
          throw const NotFoundFailure(
            message: 'Configuracao de e-mail nao encontrada',
          );
        }
        return _toEntity(config);
      },
    );
  }

  @override
  Future<rd.Result<EmailConfig>> create(EmailConfig config) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar configuracao de e-mail',
      action: () async {
        await _syncCredentialSecretsOrThrow(config: config);
        await _database.emailConfigDao.insertConfig(_toCompanion(config));
        return config;
      },
    );
  }

  @override
  Future<rd.Result<EmailConfig>> update(EmailConfig config) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar configuracao de e-mail',
      action: () async {
        final existing = await _database.emailConfigDao.getById(config.id);
        await _syncCredentialSecretsOrThrow(
          config: config,
          existing: existing,
        );

        final updated = await _database.emailConfigDao.updateConfig(
          _toCompanion(config),
        );
        if (!updated) {
          throw const NotFoundFailure(
            message: 'Configuracao de e-mail nao encontrada',
          );
        }
        return config;
      },
    );
  }

  @override
  Future<rd.Result<EmailConfig>> saveWithPrimaryTarget({
    required EmailConfig config,
    required String primaryRecipientEmail,
  }) async {
    final recipient = primaryRecipientEmail.trim();
    if (recipient.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Informe ao menos um e-mail destinatario na configuracao SMTP',
        ),
      );
    }

    return RepositoryGuard.run(
      errorMessage:
          'Erro ao salvar configuracao de e-mail com destinatario principal',
      action: () async {
        final existing = await _database.emailConfigDao.getById(config.id);

        await _database.transaction(() async {
          await _syncCredentialSecretsOrThrow(
            config: config,
            existing: existing,
          );

          // Re-checa dentro da transação porque entre `getById` (linha
          // acima) e o início da transação a row pode ter sido removida
          // por outro fluxo concorrente. O custo extra é o de uma query
          // simples, e a alternativa (TOCTOU silencioso) é pior.
          final existingRow = await _database.emailConfigDao.getById(
            config.id,
          );
          if (existingRow == null) {
            await _database.emailConfigDao.insertConfig(_toCompanion(config));
          } else {
            final updated = await _database.emailConfigDao.updateConfig(
              _toCompanion(config),
            );
            if (!updated) {
              throw const NotFoundFailure(
                message: 'Configuracao de e-mail nao encontrada',
              );
            }
          }

          await _database.emailNotificationTargetDao.deleteByConfigId(
            config.id,
          );

          final now = DateTime.now();
          final targetId = '${config.id}:$recipient';
          await _database.emailNotificationTargetDao.insertTarget(
            EmailNotificationTargetsTableCompanion(
              id: Value(targetId),
              emailConfigId: Value(config.id),
              recipientEmail: Value(recipient),
              notifyOnSuccess: Value(config.notifyOnSuccess),
              notifyOnError: Value(config.notifyOnError),
              notifyOnWarning: Value(config.notifyOnWarning),
              enabled: Value(config.enabled),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        });

        return config;
      },
    );
  }

  @override
  Future<rd.Result<void>> deleteById(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar configuracao de e-mail',
      action: () async {
        final existing = await _database.emailConfigDao.getById(id);
        final passwordKey = existing == null
            ? _buildSmtpPasswordKey(id)
            : _resolvePasswordKey(existing);
        final oauthTokenKey = existing == null
            ? null
            : _resolveOAuthTokenKey(existing, fallbackConfigId: id);
        await _secureCredentialService.deletePassword(key: passwordKey);
        if (oauthTokenKey != null && oauthTokenKey.isNotEmpty) {
          await _secureCredentialService.deleteToken(key: oauthTokenKey);
        }
        await _database.emailConfigDao.deleteById(id);
      },
    );
  }

  @override
  Future<rd.Result<EmailConfig>> get() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar configuracao de e-mail',
      action: () async {
        final configs = await _database.emailConfigDao.getAll();
        if (configs.isEmpty) {
          throw const NotFoundFailure(
            message: 'Configuracao de e-mail nao encontrada',
          );
        }
        return _toEntity(configs.first);
      },
    );
  }

  @override
  Future<rd.Result<EmailConfig>> save(EmailConfig config) async {
    // O try/catch original wrappava `create()` e `update()` mas estes já
    // retornam `Result` (não throwam). O catch só protegia o `getById`
    // inicial. Agora delegamos a checagem ao `RepositoryGuard.run` somente
    // no `getById`; create/update já cuidam dos próprios erros.
    final lookupResult = await RepositoryGuard.run<EmailConfigsTableData>(
      errorMessage: 'Erro ao salvar configuracao de e-mail',
      action: () async {
        final existing = await _database.emailConfigDao.getById(config.id);
        if (existing == null) {
          throw _MissingExistingRowSentinel();
        }
        return existing;
      },
    );

    return lookupResult.fold(
      (_) => update(config),
      (failure) {
        // O sentinel sinaliza "não existe ainda → criar". Qualquer outra
        // falha é um erro real de I/O e deve ser propagado.
        final original =
            failure is DatabaseFailure ? failure.originalError : null;
        if (original is _MissingExistingRowSentinel) {
          return create(config);
        }
        return Future.value(rd.Failure(failure));
      },
    );
  }

  @override
  Future<rd.Result<void>> delete() {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar configuracoes de e-mail',
      action: () async {
        final rows = await _database.emailConfigDao.getAll();
        for (final row in rows) {
          final passwordKey = _resolvePasswordKey(row);
          await _secureCredentialService.deletePassword(key: passwordKey);
          final oauthTokenKey = _resolveOAuthTokenKey(
            row,
            fallbackConfigId: row.id,
          );
          if (oauthTokenKey != null && oauthTokenKey.isNotEmpty) {
            await _secureCredentialService.deleteToken(key: oauthTokenKey);
          }
        }
        await _database.emailConfigDao.deleteAll();
      },
    );
  }

  Future<EmailConfig> _toEntity(EmailConfigsTableData data) async {
    List<String> recipients;
    try {
      recipients = (jsonDecode(data.recipients) as List).cast<String>();
    } on Object catch (e) {
      LoggerService.warning(
        '[EmailConfigRepository] Erro ao decodificar recipients para config ${data.id}: $e',
      );
      recipients = [];
    }

    final passwordKey = _resolvePasswordKey(data);
    final authMode = SmtpAuthMode.fromValue(data.authMode);
    final oauthProvider = SmtpOAuthProvider.fromValue(
      (data.oauthProvider ?? '').trim(),
    );
    final oauthTokenKey = _resolveOAuthTokenKey(
      data,
      fallbackConfigId: data.id,
      fallbackProvider: oauthProvider,
    );
    var password = '';
    if (authMode == SmtpAuthMode.password) {
      final securePasswordResult = await _secureCredentialService.getPassword(
        key: passwordKey,
      );
      password = securePasswordResult.getOrElse((_) => '');
    }

    if (authMode == SmtpAuthMode.password &&
        password.isEmpty &&
        data.password.trim().isNotEmpty) {
      final legacyPassword = data.password;
      final migrateResult = await _secureCredentialService.storePassword(
        key: passwordKey,
        password: legacyPassword,
      );
      if (migrateResult.isSuccess()) {
        password = legacyPassword;
        await _database.customStatement(
          '''
          UPDATE email_configs_table
          SET password = '', smtp_password_key = ?
          WHERE id = ?
          ''',
          [passwordKey, data.id],
        );
      } else {
        LoggerService.warning(
          '[EmailConfigRepository] Falha ao migrar senha SMTP legada para secure storage: '
          'configId=${data.id}',
        );
        password = legacyPassword;
      }
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
      password: password,
      useSsl: data.useSsl,
      authMode: authMode,
      oauthProvider: oauthProvider,
      oauthAccountEmail: data.oauthAccountEmail?.trim().isEmpty ?? true
          ? null
          : data.oauthAccountEmail!.trim(),
      oauthTokenKey: oauthTokenKey,
      oauthConnectedAt: data.oauthConnectedAt,
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
    final passwordKey = _buildSmtpPasswordKey(config.id);
    final oauthTokenKey = _resolveOAuthTokenKeyFromConfig(config);
    return EmailConfigsTableCompanion(
      id: Value(config.id),
      configName: Value(config.configName),
      senderName: Value(config.senderName),
      fromEmail: Value(config.fromEmail),
      fromName: Value(config.fromName),
      smtpServer: Value(config.smtpServer),
      smtpPort: Value(config.smtpPort),
      username: Value(config.username),
      password: const Value(''),
      smtpPasswordKey: Value(passwordKey),
      useSsl: Value(config.useSsl),
      authMode: Value(config.authMode.value),
      oauthProvider: Value(config.oauthProvider?.value),
      oauthAccountEmail: Value(_normalizeOptional(config.oauthAccountEmail)),
      oauthTokenKey: Value(_normalizeOptional(oauthTokenKey)),
      oauthConnectedAt: Value(config.oauthConnectedAt),
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

  String _buildSmtpPasswordKey(String configId) {
    return '$_smtpPasswordKeyPrefix$configId';
  }

  String _buildOAuthTokenKey(String configId, SmtpOAuthProvider provider) {
    return '$_smtpOAuthTokenKeyPrefix${provider.value}_$configId';
  }

  String _resolvePasswordKey(EmailConfigsTableData data) {
    final dbKey = data.smtpPasswordKey.trim();
    if (dbKey.isNotEmpty) {
      return dbKey;
    }
    return _buildSmtpPasswordKey(data.id);
  }

  String? _resolveOAuthTokenKey(
    EmailConfigsTableData data, {
    required String fallbackConfigId,
    SmtpOAuthProvider? fallbackProvider,
  }) {
    final dbKey = (data.oauthTokenKey ?? '').trim();
    if (dbKey.isNotEmpty) {
      return dbKey;
    }
    final provider =
        fallbackProvider ??
        SmtpOAuthProvider.fromValue((data.oauthProvider ?? '').trim());
    if (provider == null) {
      return null;
    }
    return _buildOAuthTokenKey(fallbackConfigId, provider);
  }

  String? _resolveOAuthTokenKeyFromConfig(EmailConfig config) {
    final key = config.oauthTokenKey?.trim();
    if (key != null && key.isNotEmpty) {
      return key;
    }
    final provider = config.oauthProvider;
    if (provider == null) {
      return null;
    }
    return _buildOAuthTokenKey(config.id, provider);
  }

  String? _normalizeOptional(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  /// Wrapper que joga (em vez de retornar) a falha do `_syncCredentialSecrets`,
  /// permitindo que o `RepositoryGuard.run` ou a `_database.transaction()`
  /// pegue e propague. Sem isso, cada caller tinha um `if (result.isError())
  /// return rd.Failure(result.exceptionOrNull()!);` repetido.
  Future<void> _syncCredentialSecretsOrThrow({
    required EmailConfig config,
    EmailConfigsTableData? existing,
  }) async {
    final result = await _syncCredentialSecrets(
      config: config,
      existing: existing,
    );
    if (result.isError()) {
      throw result.exceptionOrNull()!;
    }
  }

  Future<rd.Result<void>> _syncCredentialSecrets({
    required EmailConfig config,
    EmailConfigsTableData? existing,
  }) async {
    final passwordKey = _buildSmtpPasswordKey(config.id);
    final targetOauthTokenKey = _resolveOAuthTokenKeyFromConfig(config);
    final existingOauthTokenKey = existing == null
        ? null
        : _resolveOAuthTokenKey(
            existing,
            fallbackConfigId: config.id,
          );

    if (config.authMode == SmtpAuthMode.password) {
      final storePasswordResult = await _secureCredentialService.storePassword(
        key: passwordKey,
        password: config.password,
      );
      if (storePasswordResult.isError()) {
        return rd.Failure(storePasswordResult.exceptionOrNull()!);
      }

      if (existingOauthTokenKey != null && existingOauthTokenKey.isNotEmpty) {
        await _secureCredentialService.deleteToken(key: existingOauthTokenKey);
      }
      return const rd.Success(unit);
    }

    await _secureCredentialService.deletePassword(key: passwordKey);

    if (targetOauthTokenKey == null || targetOauthTokenKey.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Token OAuth SMTP nao configurado para o modo selecionado',
        ),
      );
    }

    if (existingOauthTokenKey != null &&
        existingOauthTokenKey.isNotEmpty &&
        existingOauthTokenKey != targetOauthTokenKey) {
      await _secureCredentialService.deleteToken(key: existingOauthTokenKey);
    }

    final hasToken = await _secureCredentialService.containsKey(
      key: targetOauthTokenKey,
    );
    if (hasToken.isError()) {
      return rd.Failure(hasToken.exceptionOrNull()!);
    }
    if (!hasToken.getOrElse((_) => false)) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Conexao OAuth SMTP nao encontrada. Conecte a conta antes de salvar.',
        ),
      );
    }

    return const rd.Success(unit);
  }

}

/// Sentinel para o `save()`: sinaliza que `getById` retornou `null` (não
/// existe ainda), e que o caller deve rotear para `create()` em vez de
/// `update()`. Evita ter que retornar um valor "magic null" ou um Result
/// composto.
class _MissingExistingRowSentinel implements Exception {
  @override
  String toString() => 'EmailConfig row does not exist; route to create';
}
