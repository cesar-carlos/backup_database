import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_postgres_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sql_server_config_repository.dart';
import 'package:backup_database/domain/repositories/i_sybase_config_repository.dart';
import 'package:backup_database/domain/services/i_sql_script_execution_service.dart';
import 'package:result_dart/result_dart.dart';

/// Service for orchestrating post-backup script execution.
///
/// This service handles the execution of SQL scripts after a backup
/// is completed, including retrieving the appropriate database
/// configuration and logging the results.
abstract class IBackupScriptOrchestrator {
  /// Executes a post-backup SQL script for the given schedule.
  ///
  /// Parameters:
  /// - [historyId]: The backup history ID for logging
  /// - [schedule]: The schedule containing the script to execute
  /// - [sqlServerConfigRepository]: Repository for SQL Server configs
  /// - [sybaseConfigRepository]: Repository for Sybase configs
  /// - [postgresConfigRepository]: Repository for PostgreSQL configs
  /// - [scriptService]: Service for executing SQL scripts
  /// - [logRepository]: Repository for logging execution results
  ///
  /// Returns [Success] if the script executed successfully or was
  /// gracefully handled, [Failure] if a critical error occurred.
  Future<Result<void>> executePostBackupScript({
    required String historyId,
    required Schedule schedule,
    required ISqlServerConfigRepository sqlServerConfigRepository,
    required ISybaseConfigRepository sybaseConfigRepository,
    required IPostgresConfigRepository postgresConfigRepository,
    required ISqlScriptExecutionService scriptService,
    required IBackupLogRepository logRepository,
  });
}
