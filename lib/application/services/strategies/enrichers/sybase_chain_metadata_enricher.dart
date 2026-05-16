import 'package:backup_database/application/services/strategies/backup_pipeline_context.dart';
import 'package:backup_database/application/services/strategies/backup_result_enricher.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';

class SybaseChainMetadataEnricher extends BackupResultEnricher<SybaseConfig> {
  @override
  Future<BackupExecutionResult> enrich(
    BackupPipelineContext context, {
    required Schedule schedule,
    required SybaseConfig config,
    required BackupType backupType,
    required BackupExecutionResult result,
  }) async {
    final preflight = context.sybaseLogPreflight;
    if (preflight == null) {
      return result;
    }
    if (preflight.baseFull == null || preflight.nextLogSequence == null) {
      return result;
    }

    final base = result.metrics?.sybaseOptions != null
        ? Map<String, dynamic>.from(result.metrics!.sybaseOptions!)
        : <String, dynamic>{};
    final baseFull = preflight.baseFull!;
    base['baseFullId'] = baseFull.id;
    base['chainStartAt'] = (baseFull.finishedAt ?? baseFull.startedAt)
        .toIso8601String();
    base['logSequence'] = preflight.nextLogSequence;
    final enrichedMetrics = result.metrics?.copyWith(sybaseOptions: base);
    return BackupExecutionResult(
      backupPath: result.backupPath,
      fileSize: result.fileSize,
      duration: result.duration,
      databaseName: result.databaseName,
      metrics: enrichedMetrics ?? result.metrics,
      executedBackupType: result.executedBackupType,
    );
  }
}
