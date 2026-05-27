import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/machine_bootstrap_flag_store.dart';
import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Bug fix one-shot do release 2.2.3: dropa as tabelas de config dos
/// SGBDs (SQL Server, Sybase, Postgres) renomeando para `*_backup_v2_2_3_<ts>`
/// para que o Drift recrie no próximo acesso. Roda **exatamente** quando
/// `currentVersion == 2.2.3` e a flag de marker não existe.
///
/// Antes vivia inline em `core_module.dart` (~300 linhas no meio do
/// setup do DI). Extraído porque migration ≠ DI: facilita rodar isolado
/// em testes e mantém o `core_module` legível.
abstract final class DatabaseConfigTablesDropV223 {
  static const String _legacyResetFlagKey = 'reset_v2_2_3_done';
  static const String _databaseFileName = 'backup_database.db';
  static final Version _targetVersion = Version(2, 2, 3);

  static const List<String> _tablesToDrop = <String>[
    'sql_server_configs_table',
    'sybase_configs_table',
    'postgres_configs_table',
  ];

  // Espera defensiva: outras inicializações early-boot podem ainda estar
  // segurando o handle do SQLite por alguns ms (open exclusivo do Drift,
  // migration do machine scope). Sem essa espera o `sqlite3.open` aqui
  // ocasionalmente recebia `SQLITE_BUSY`.
  static const Duration _initialWait = Duration(milliseconds: 500);

  /// Executa o drop se aplicável. Retorna `true` se o drop foi executado
  /// (e a flag marcada); `false` caso contrário.
  ///
  /// Os parâmetros são todos opcionais e existem para permitir teste
  /// puro: production injeta os defaults reais (PackageInfo, machine
  /// data dir, machine bootstrap flag store).
  static Future<bool> run({
    Duration? initialWait,
    Future<String> Function()? appVersionProvider,
    Future<Directory> Function()? machineDataDirectoryProvider,
    Future<bool> Function()? hasAlreadyReset,
    Future<void> Function()? markResetCompleted,
  }) async {
    await Future<void>.delayed(initialWait ?? _initialWait);

    final rawVersion = await (appVersionProvider ?? _defaultAppVersion)();
    final metrics = _DropMetrics();

    metrics.start(_DropPhase.validation);
    LoggerService.info('===== CONFIG TABLES DROP CHECK =====');
    LoggerService.info('Versão do app: $rawVersion');
    LoggerService.info('Target version: $_targetVersion');

    final Version currentVersion;
    try {
      currentVersion = Version.parse(rawVersion.split('+').first);
    } on Exception catch (e) {
      LoggerService.warning('Versão inválida "$rawVersion": $e');
      return false;
    }

    final shouldReset = currentVersion == _targetVersion;
    LoggerService.info(
      'Versão parseada: $currentVersion, Target: $_targetVersion, '
      'Reset: $shouldReset',
    );

    if (!shouldReset) {
      LoggerService.info(
        'Versão não é exatamente $_targetVersion, pulando drop de tabelas',
      );
      return false;
    }

    if (await (hasAlreadyReset ?? _defaultHasAlreadyReset)()) {
      LoggerService.info(
        'Reset v$_targetVersion já foi executado anteriormente',
      );
      return false;
    }
    metrics.stop(_DropPhase.validation);

    sqlite3.Database? database;
    try {
      final resolveDir =
          machineDataDirectoryProvider ?? resolveMachineDataDirectory;
      final machineDataDir = await resolveDir();
      final dbPath = p.join(machineDataDir.path, _databaseFileName);
      if (!await File(dbPath).exists()) {
        return false;
      }

      final backupSuffix =
          '_backup_v2_2_3_${DateTime.now().millisecondsSinceEpoch}';

      metrics.start(_DropPhase.dbOpen);
      LoggerService.info('FASE 2: Abertura do banco');
      database = sqlite3.sqlite3.open(dbPath);
      metrics.stop(_DropPhase.dbOpen);

      metrics.start(_DropPhase.backupCreation);
      LoggerService.info('FASE 3: Criação de backups');
      for (final tableName in _tablesToDrop) {
        final backupTableName = '$tableName$backupSuffix';
        database.execute(
          'ALTER TABLE $tableName RENAME TO $backupTableName',
        );
        LoggerService.info('Backup criado: $backupTableName');
      }
      metrics.stop(_DropPhase.backupCreation);

      LoggerService.warning('===== INICIANDO DROP DE TABELAS DE CONFIG =====');

      metrics.start(_DropPhase.dropExecution);
      database.execute('BEGIN IMMEDIATE TRANSACTION');
      LoggerService.info('FASE 4: DROP de tabelas - Transação iniciada');

      try {
        for (final tableName in _tablesToDrop) {
          try {
            database.execute('DROP TABLE IF EXISTS $tableName');
            LoggerService.warning('Tabela dropada: $tableName');
          } on Exception catch (e) {
            LoggerService.warning('Erro ao dropar tabela $tableName: $e');
          }
        }
        database.execute('COMMIT');
      } on Object catch (e) {
        database.execute('ROLLBACK');
        _handleDropError(e);
        return false;
      }
      metrics.stop(_DropPhase.dropExecution);

      metrics.start(_DropPhase.cleanup);
      database.dispose();
      database = null;
      LoggerService.warning(
        '===== DROP DE TABELAS CONCLUÍDO, BACKUPS DISPONÍVEIS =====',
      );
      await (markResetCompleted ?? _defaultMarkResetCompleted)();
      LoggerService.info(
        'Tabelas serão recriadas automaticamente pelo Drift no próximo '
        'acesso. Backups disponíveis para rollback.',
      );
      metrics.stop(_DropPhase.cleanup);

      metrics.logSummary();
      return true;
    } on Object catch (e) {
      _handleDropError(e);
      return false;
    } finally {
      database?.dispose();
    }
  }

  static Future<String> _defaultAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  static Future<bool> _defaultHasAlreadyReset() async {
    try {
      return await hasMachineBootstrapFlag(
        fileName: MachineStorageLayout.resetV223Marker,
        legacySecureStorageKey: _legacyResetFlagKey,
      );
    } on Object catch (e) {
      LoggerService.warning('Erro ao ler flag de reset: $e');
      return false;
    }
  }

  static Future<void> _defaultMarkResetCompleted() async {
    try {
      await markMachineBootstrapFlag(
        fileName: MachineStorageLayout.resetV223Marker,
        legacySecureStorageKey: _legacyResetFlagKey,
      );
      LoggerService.info(
        'Flag de reset v$_targetVersion marcada como concluída',
      );
    } on Object catch (e) {
      LoggerService.warning('Erro ao gravar flag de reset: $e');
    }
  }

  static void _handleDropError(Object error) {
    final errorType = _categorizeError(error);
    switch (errorType) {
      case _DropErrorType.critical:
        LoggerService.error(
          'CRÍTICO: Operação de drop não pode continuar: $error',
        );
      case _DropErrorType.expected:
        LoggerService.info('Esperado: ${_errorTypeLabel(errorType)}: $error');
      case _DropErrorType.recoverable:
        LoggerService.warning(
          'Recuperável: ${_errorTypeLabel(errorType)}: $error',
        );
    }
  }

  static _DropErrorType _categorizeError(Object error) {
    if (error case final sqlite3.SqliteException sqliteError) {
      final code = sqliteError.extendedResultCode;
      if (code == sqlite3.SqlError.SQLITE_CONSTRAINT ||
          code == sqlite3.SqlError.SQLITE_CORRUPT ||
          code == sqlite3.SqlError.SQLITE_NOTADB ||
          code == sqlite3.SqlError.SQLITE_FORMAT ||
          code == sqlite3.SqlError.SQLITE_FULL) {
        return _DropErrorType.critical;
      }
      if (code == sqlite3.SqlError.SQLITE_BUSY ||
          code == sqlite3.SqlError.SQLITE_LOCKED) {
        return _DropErrorType.recoverable;
      }
      return _DropErrorType.expected;
    }
    if (error case final FileSystemException fsError) {
      const accessDenied = 5;
      const sharingViolation = 32;
      if (fsError.osError?.errorCode == accessDenied ||
          fsError.osError?.errorCode == sharingViolation) {
        return _DropErrorType.critical;
      }
      return _DropErrorType.recoverable;
    }
    return _DropErrorType.recoverable;
  }

  static String _errorTypeLabel(_DropErrorType type) {
    switch (type) {
      case _DropErrorType.critical:
        return 'Erro fatal';
      case _DropErrorType.expected:
        return 'Condição normal';
      case _DropErrorType.recoverable:
        return 'Erro recuperável';
    }
  }
}

enum _DropPhase {
  validation,
  dbOpen,
  backupCreation,
  dropExecution,
  cleanup,
}

enum _DropErrorType { critical, expected, recoverable }

class _DropMetrics {
  final Map<_DropPhase, Stopwatch> _stopwatches = <_DropPhase, Stopwatch>{};

  void start(_DropPhase phase) {
    _stopwatches[phase] = Stopwatch()..start();
  }

  void stop(_DropPhase phase) {
    _stopwatches[phase]?.stop();
  }

  int elapsedMs(_DropPhase phase) =>
      _stopwatches[phase]?.elapsedMilliseconds ?? 0;

  int get totalMs => _DropPhase.values.fold<int>(
    0,
    (sum, phase) => sum + elapsedMs(phase),
  );

  void logSummary() {
    LoggerService.info('===== RESUMO DE PERFORMANCE =====');
    for (final phase in _DropPhase.values) {
      LoggerService.info('${phase.name}: ${elapsedMs(phase)}ms');
    }
    LoggerService.info('TOTAL: ${totalMs}ms');
  }
}
