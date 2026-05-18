import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:backup_database/domain/use_cases/storage/validate_backup_directory.dart';
import 'package:backup_database/infrastructure/external/compression/winrar_service.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/socket/server/preflight_message_handler.dart';

const int _minFreeBytesWarning = 5 * 1024 * 1024 * 1024;

Map<String, PreflightCheck> buildServerPreflightChecks({
  required String stagingBasePath,
  required ValidateBackupDirectory validateBackupDirectory,
  required IStorageChecker storageChecker,
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
  };
}
