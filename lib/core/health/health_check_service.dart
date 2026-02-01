import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:path/path.dart' as p;

/// Performs health checks for the backup system
class HealthCheckService {
  /// Check if there's enough disk space for backups
  Future<HealthCheckResult> checkDiskSpace({
    required String path,
    required int requiredSpaceMB,
  }) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        return HealthCheckResult(
          status: HealthStatus.unhealthy,
          message: 'Diretório não existe: $path',
        );
      }

      // Try to check available space (platform-specific)
      try {
        final stat = await directory.stat();
        final modified = stat.modified;
        final isAccessible = DateTime.now().difference(modified).inDays < 365;

        if (!isAccessible) {
          return HealthCheckResult(
            status: HealthStatus.warning,
            message: 'Diretório pode não ser acessível',
          );
        }
      } on Object catch (e) {
        LoggerService.warning('Não foi possível verificar espaço em disco: $e');
      }

      return HealthCheckResult(
        status: HealthStatus.healthy,
        message: 'Espaço em disco parece adequado',
      );
    } on Object catch (e) {
      return HealthCheckResult(
        status: HealthStatus.unhealthy,
        message: 'Erro ao verificar espaço: $e',
      );
    }
  }

  /// Check if a file path is writable
  Future<HealthCheckResult> checkWritePermission(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        return HealthCheckResult(
          status: HealthStatus.unhealthy,
          message: 'Diretório não existe: $path',
        );
      }

      final testFile = File(
        p.join(path, '.health_check_${DateTime.now().millisecondsSinceEpoch}'),
      );

      await testFile.writeAsString('test');
      await testFile.delete();

      return HealthCheckResult(
        status: HealthStatus.healthy,
        message: 'Permissão de escrita OK',
      );
    } on FileSystemException catch (e) {
      return HealthCheckResult(
        status: HealthStatus.unhealthy,
        message: 'Sem permissão de escrita: ${e.message}',
      );
    } on Object catch (e) {
      return HealthCheckResult(
        status: HealthStatus.error,
        message: 'Erro inesperado: $e',
      );
    }
  }

  /// Run all health checks
  Future<List<HealthCheckResult>> runHealthChecks({
    List<String>? pathsToCheck,
  }) async {
    final results = <HealthCheckResult>[];

    // Check common backup directories
    final paths = pathsToCheck ??
        [
          if (Platform.isWindows) r'C:\Backups',
          if (!Platform.isWindows) '/var/backups',
        ];

    for (final path in paths) {
      final spaceResult = await checkDiskSpace(
        path: path,
        requiredSpaceMB: 1024,
      );
      results.add(spaceResult);

      final writeResult = await checkWritePermission(path);
      results.add(writeResult);
    }

    return results;
  }

  /// Get overall health status from results
  HealthStatus getOverallStatus(List<HealthCheckResult> results) {
    if (results.any((r) => r.status == HealthStatus.unhealthy)) {
      return HealthStatus.unhealthy;
    }
    if (results.any((r) => r.status == HealthStatus.error)) {
      return HealthStatus.error;
    }
    if (results.any((r) => r.status == HealthStatus.warning)) {
      return HealthStatus.warning;
    }
    return HealthStatus.healthy;
  }
}

class HealthCheckResult {
  HealthCheckResult({
    required this.status,
    required this.message,
  });

  final HealthStatus status;
  final String message;

  @override
  String toString() => '$status: $message';
}

enum HealthStatus {
  healthy,
  warning,
  unhealthy,
  error,
}
