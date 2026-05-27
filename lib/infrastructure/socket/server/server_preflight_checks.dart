import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart'
    show DatabaseType;
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:backup_database/domain/use_cases/backup/validate_sybase_log_backup_preflight.dart';
import 'package:backup_database/domain/use_cases/storage/validate_backup_directory.dart';
import 'package:backup_database/infrastructure/external/compression/winrar_service.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/socket/server/preflight_message_handler.dart';

const int _minFreeBytesWarning = 5 * 1024 * 1024 * 1024;

Map<String, PreflightCheck> buildServerPreflightChecks({
  required String stagingBasePath,
  required ValidateBackupDirectory validateBackupDirectory,
  required IStorageChecker storageChecker,
  // PR-6: validacao opcional de cadeia de log Sybase. Quando ambos
  // estao injetados, o check `sybase_log_backup` percorre todos os
  // schedules Sybase com `backupType == log` e reporta o primeiro
  // com cadeia comprometida (severity=warning, nao bloqueia outros).
  IScheduleRepository? scheduleRepository,
  ValidateSybaseLogBackupPreflight? validateSybaseLogPreflight,
}) {
  return {
    'compression_tool': () async {
      final installed = await WinRarService.isInstalledInSystem();
      if (installed) {
        return const PreflightCheckResult(
          name: 'compression_tool',
          passed: true,
          severity: PreflightSeverity.info,
          message: 'WinRAR detectado no servidor',
        );
      }
      return const PreflightCheckResult(
        name: 'compression_tool',
        passed: false,
        severity: PreflightSeverity.warning,
        message:
            'WinRAR não encontrado; backups ZIP seguem disponíveis, '
            'mas agendamentos RAR podem falhar no servidor',
      );
    },
    'temp_dir_writable': () async {
      final result = await validateBackupDirectory(stagingBasePath);
      return result.fold(
        (_) => const PreflightCheckResult(
          name: 'temp_dir_writable',
          passed: true,
          severity: PreflightSeverity.blocking,
          message: 'Pasta de staging do servidor gravável',
        ),
        (failure) => PreflightCheckResult(
          name: 'temp_dir_writable',
          passed: false,
          severity: PreflightSeverity.blocking,
          message: failure is Failure ? failure.message : failure.toString(),
        ),
      );
    },
    'disk_space': () async {
      final result = await storageChecker.checkSpace(stagingBasePath);
      return result.fold(
        (info) {
          final hasEnough = info.hasEnoughSpace(_minFreeBytesWarning);
          return PreflightCheckResult(
            name: 'disk_space',
            passed: hasEnough,
            severity: PreflightSeverity.warning,
            message: hasEnough
                ? 'Espaço livre: ${ByteFormat.format(info.freeBytes)}'
                : 'Pouco espaço em disco no servidor '
                      '(livre: ${ByteFormat.format(info.freeBytes)}; '
                      'recomendado ≥ ${ByteFormat.format(_minFreeBytesWarning)})',
            details: {
              'freeBytes': info.freeBytes,
              'totalBytes': info.totalBytes,
            },
          );
        },
        (failure) => PreflightCheckResult(
          name: 'disk_space',
          passed: false,
          severity: PreflightSeverity.warning,
          message: failure is Failure ? failure.message : failure.toString(),
        ),
      );
    },
    // PR-6: cadeia de log Sybase. Percorre todos os schedules ativos
    // que usam log backup Sybase e reporta o primeiro com cadeia
    // comprometida (sem base full, ou base expirada). Quando nao houver
    // schedule Sybase log, retorna `passed=true info` (sem ruido).
    if (scheduleRepository != null && validateSybaseLogPreflight != null)
      'sybase_log_backup': () async {
        try {
          final schedulesResult = await scheduleRepository.getEnabled();
          final schedules = schedulesResult.getOrNull() ?? const [];
          final sybaseLogSchedules = schedules
              .where((s) {
                if (s.databaseType != DatabaseType.sybase) return false;
                final effectiveType = s.backupType == BackupType.fullSingle
                    ? BackupType.full
                    : s.backupType;
                return effectiveType == BackupType.log;
              })
              .toList(growable: false);

          if (sybaseLogSchedules.isEmpty) {
            return const PreflightCheckResult(
              name: 'sybase_log_backup',
              passed: true,
              severity: PreflightSeverity.info,
              message: 'Nenhum agendamento Sybase log ativo',
            );
          }

          final issues = <String>[];
          for (final schedule in sybaseLogSchedules) {
            final result = await validateSybaseLogPreflight(schedule);
            final outcome = result.getOrNull();
            if (outcome == null) continue;
            if (!outcome.canProceed && outcome.error != null) {
              issues.add('${schedule.name}: ${outcome.error}');
            } else if (outcome.warning != null) {
              issues.add('${schedule.name}: ${outcome.warning}');
            }
          }

          if (issues.isEmpty) {
            return PreflightCheckResult(
              name: 'sybase_log_backup',
              passed: true,
              severity: PreflightSeverity.info,
              message:
                  '${sybaseLogSchedules.length} agendamento(s) Sybase log '
                  'com cadeia saudavel',
            );
          }

          return PreflightCheckResult(
            name: 'sybase_log_backup',
            passed: false,
            // Severity warning para nao bloquear outros backups —
            // problemas reais aparecem na execucao do schedule especifico.
            severity: PreflightSeverity.warning,
            message:
                'Cadeia de log Sybase com problemas em '
                '${issues.length}/${sybaseLogSchedules.length} schedule(s)',
            details: {'issues': issues},
          );
        } on Object catch (e) {
          // Defesa: erro inesperado no preflight nao quebra os outros.
          return PreflightCheckResult(
            name: 'sybase_log_backup',
            passed: false,
            severity: PreflightSeverity.warning,
            message: 'Erro ao validar cadeia de log Sybase: $e',
          );
        }
      },
  };
}
