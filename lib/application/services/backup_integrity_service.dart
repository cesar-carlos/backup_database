import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:crypto/crypto.dart';

/// Service for verifying backup file integrity
class BackupIntegrityService {
  /// Calculate SHA-256 checksum of a file
  Future<String> calculateChecksum(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw FileSystemException('Arquivo não encontrado: $filePath');
      }

      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString();
    } on Object catch (e) {
      LoggerService.error('Erro ao calcular checksum: $e');
      rethrow;
    }
  }

  /// Verify backup integrity by comparing checksums
  Future<IntegrityResult> verifyBackup({
    required String filePath,
    required String expectedChecksum,
  }) async {
    try {
      final actualChecksum = await calculateChecksum(filePath);

      if (actualChecksum == expectedChecksum) {
        return IntegrityResult(
          isValid: true,
          checksum: actualChecksum,
          message: 'Checksum confere',
        );
      }

      return IntegrityResult(
        isValid: false,
        checksum: actualChecksum,
        message: 'Checksum não confere - arquivo pode estar corrompido',
      );
    } on Object catch (e) {
      return IntegrityResult(
        isValid: false,
        checksum: '',
        message: 'Erro ao verificar integridade: $e',
        error: e,
      );
    }
  }

  /// Verify file size is within expected range
  IntegrityResult verifyFileSize({
    required String filePath,
    required int minExpectedSize,
    int? maxExpectedSize,
  }) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return IntegrityResult(
          isValid: false,
          checksum: '',
          message: 'Arquivo não encontrado',
        );
      }

      final size = file.lengthSync();

      if (size < minExpectedSize) {
        return IntegrityResult(
          isValid: false,
          checksum: '',
          message: 'Arquivo muito pequeno ($size bytes < $minExpectedSize bytes)',
        );
      }

      if (maxExpectedSize != null && size > maxExpectedSize) {
        return IntegrityResult(
          isValid: false,
          checksum: '',
          message: 'Arquivo muito grande ($size bytes > $maxExpectedSize bytes)',
        );
      }

      return IntegrityResult(
        isValid: true,
        checksum: '',
        message: 'Tamanho do arquivo OK ($size bytes)',
      );
    } on Object catch (e) {
      return IntegrityResult(
        isValid: false,
        checksum: '',
        message: 'Erro ao verificar tamanho: $e',
        error: e,
      );
    }
  }
}

class IntegrityResult {
  IntegrityResult({
    required this.isValid,
    required this.checksum,
    required this.message,
    this.error,
  });

  final bool isValid;
  final String checksum;
  final String message;
  final Object? error;

  @override
  String toString() =>
      'IntegrityResult(valid: $isValid, checksum: $checksum, message: $message)';
}
