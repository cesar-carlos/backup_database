import 'dart:io';

import 'package:backup_database/application/services/health/health_models.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';

class DiskSpaceProbe {
  DiskSpaceProbe({
    required this._processService,
    required this._diskCheckPaths,
    required this.minFreeDiskGB,
  });

  static const Duration _fsutilTimeout = Duration(seconds: 10);
  static const double _bytesPerGB = 1024 * 1024 * 1024;
  static const double _criticalFreeDiskGB = 1;

  final ProcessService _processService;
  final List<String> _diskCheckPaths;
  final double minFreeDiskGB;

  Future<HealthProbeResult> check() async {
    final issues = <HealthIssue>[];
    final metrics = <String, dynamic>{};

    if (!Platform.isWindows) {
      metrics['disk_check_performed'] = false;
      metrics['disk_check_skip_reason'] = 'Not Windows';
      return HealthProbeResult(issues, metrics);
    }

    // S1: paths a checar. Se config não foi fornecida, usa Directory.current
    // como fallback retrocompat (mas registra em metric para detecção no
    // monitoring). O ideal é o caller passar paths explícitos:
    // [appDir, programDataPath, ...activeBackupDestinationPaths].
    final pathsToCheck = _diskCheckPaths.isNotEmpty
        ? _diskCheckPaths
        : <String>[Directory.current.path];

    if (_diskCheckPaths.isEmpty) {
      metrics['disk_check_used_fallback_cwd'] = true;
    }

    final perPath = <String, double>{};
    var anyChecked = false;

    for (final pathToCheck in _uniqueDriveRoots(pathsToCheck)) {
      try {
        final result = await _processService.run(
          executable: 'fsutil',
          arguments: ['volume', 'diskfree', pathToCheck],
          timeout: _fsutilTimeout,
        );

        result.fold(
          (processResult) {
            if (processResult.exitCode != 0) {
              LoggerService.warning(
                'fsutil falhou para $pathToCheck '
                '(exit ${processResult.exitCode}): ${processResult.stderr}',
              );
              return;
            }

            final freeGB = _parseFsutilFreeBytes(processResult.stdout);
            if (freeGB == null) return;

            perPath[pathToCheck] = freeGB;
            anyChecked = true;

            if (freeGB < minFreeDiskGB) {
              issues.add(
                HealthIssue(
                  severity: freeGB < _criticalFreeDiskGB
                      ? HealthStatus.critical
                      : HealthStatus.warning,
                  category: 'disk',
                  message:
                      'Espaço em disco baixo em $pathToCheck: '
                      '${freeGB.toStringAsFixed(2)} GB livre '
                      '(mínimo: ${minFreeDiskGB.toStringAsFixed(1)} GB)',
                  details: 'Diretório verificado: $pathToCheck',
                ),
              );
            } else {
              LoggerService.debug(
                'Espaço OK em $pathToCheck: '
                '${freeGB.toStringAsFixed(2)} GB livre',
              );
            }
          },
          (failure) {
            LoggerService.warning(
              'Erro ao executar fsutil para $pathToCheck: '
              '${_issueMessage(failure)}',
            );
          },
        );
      } on Object catch (e, s) {
        LoggerService.warning(
          'Exceção ao verificar espaço em disco em $pathToCheck',
          e,
          s,
        );
      }
    }

    metrics['disk_check_performed'] = anyChecked;
    metrics['free_disk_gb_per_path'] = perPath;
    if (perPath.isNotEmpty) {
      // Métrica legada para retrocompatibilidade com dashboards antigos:
      // o menor `free_disk_gb` dentre os paths checados.
      metrics['free_disk_gb'] = perPath.values.reduce(
        (a, b) => a < b ? a : b,
      );
    }

    return HealthProbeResult(issues, metrics);
  }

  Iterable<String> _uniqueDriveRoots(List<String> paths) {
    final seen = <String>{};
    final result = <String>[];
    for (final p in paths) {
      final root = _extractDriveRoot(p);
      if (seen.add(root)) {
        result.add(root);
      }
    }
    return result;
  }

  String _extractDriveRoot(String path) {
    if (path.length >= 2 && path[1] == ':') {
      return '${path[0].toUpperCase()}:\\';
    }
    return path;
  }

  double? _parseFsutilFreeBytes(String output) {
    final lines = output.split('\n');
    for (final line in lines) {
      if (line.contains('Total free bytes')) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          final bytesStr = parts[1].trim().replaceAll(',', '');
          final totalFreeBytes = int.tryParse(bytesStr);
          if (totalFreeBytes != null) {
            return totalFreeBytes / _bytesPerGB;
          }
        }
      }
    }
    return null;
  }

  String _issueMessage(Object? failure) => healthIssueMessage(failure);
}
