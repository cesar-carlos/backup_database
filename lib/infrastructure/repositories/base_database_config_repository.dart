import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/database_connection_config.dart';
import 'package:backup_database/domain/services/i_secure_credential_service.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:backup_database/infrastructure/repositories/secure_credential_helper.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class BaseDatabaseConfigRepository<
  TConfig extends DatabaseConnectionConfig,
  TRow
> {
  BaseDatabaseConfigRepository(
    this.database,
    ISecureCredentialService secureCredentialService,
  ) : credentials = SecureCredentialHelper(secureCredentialService);

  final AppDatabase database;

  final SecureCredentialHelper credentials;

  String credentialKeyFor(String configId);

  Future<List<TRow>> fetchAllRows();

  Future<List<TRow>> fetchEnabledRows();

  Future<TRow?> fetchRowById(String id);

  Future<void> writeInsert(TConfig config);

  Future<void> writeUpdate(TConfig config);

  Future<void> writeDelete(String id);

  Future<TConfig> rowToEntity(TRow row);

  Future<void> onBeforeDelete(String id) async {}

  Future<rd.Result<List<TConfig>>> getAll() {
    return RepositoryGuard.run<List<TConfig>>(
      errorMessage: 'Erro ao buscar configurações',
      action: () async {
        final rows = await fetchAllRows();
        return [for (final row in rows) await rowToEntity(row)];
      },
    );
  }

  Future<rd.Result<List<TConfig>>> getEnabled() {
    return RepositoryGuard.run<List<TConfig>>(
      errorMessage: 'Erro ao buscar configurações ativas',
      action: () async {
        final rows = await fetchEnabledRows();
        return [for (final row in rows) await rowToEntity(row)];
      },
    );
  }

  Future<rd.Result<TConfig>> getById(String id) {
    return RepositoryGuard.run<TConfig>(
      errorMessage: 'Erro ao buscar configuração',
      action: () async {
        final row = await fetchRowById(id);
        if (row == null) {
          throw const NotFoundFailure(message: 'Configuração não encontrada');
        }
        return rowToEntity(row);
      },
    );
  }

  Future<rd.Result<TConfig>> create(TConfig config) {
    return RepositoryGuard.run<TConfig>(
      errorMessage: 'Erro ao criar configuração',
      action: () async {
        await credentials.storePasswordOrThrow(
          key: credentialKeyFor(config.id),
          password: config.password,
        );
        await writeInsert(config);
        return config;
      },
    );
  }

  Future<rd.Result<TConfig>> update(TConfig config) {
    return RepositoryGuard.run<TConfig>(
      errorMessage: 'Erro ao atualizar configuração',
      action: () async {
        await credentials.storePasswordOrThrow(
          key: credentialKeyFor(config.id),
          password: config.password,
        );
        await writeUpdate(config);
        return config;
      },
    );
  }

  Future<rd.Result<void>> delete(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar configuração',
      action: () async {
        await onBeforeDelete(id);
        await credentials.deletePassword(credentialKeyFor(id));
        await writeDelete(id);
      },
    );
  }
}
