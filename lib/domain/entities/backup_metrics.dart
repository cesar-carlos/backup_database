import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:uuid/uuid.dart';

enum BackupFailureReason {
  timeout,
  sqlError,
  fileNotFound,
  fileEmpty,
  verifyFail,
  unknown,
}

class BackupMetrics {
  BackupMetrics({
    required this.scheduleId,
    required this.databaseName,
    required this.backupType,
    this.totalDuration,
    this.backupDuration,
    this.verifyDuration,
    this.throughputMbps,
    this.fileSizeBytes,
    this.enableChecksum = false,
    this.compressionEnabled = false,
    this.failureReason,
    this.errorMessage,
    String? id,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String scheduleId;
  final String databaseName;
  final BackupType backupType;
  final Duration? totalDuration;
  final Duration? backupDuration;
  final Duration? verifyDuration;
  final double? throughputMbps;
  final int? fileSizeBytes;
  final bool enableChecksum;
  final bool compressionEnabled;
  final BackupFailureReason? failureReason;
  final String? errorMessage;
  final DateTime createdAt;

  bool get isSuccess => failureReason == null;

  Map<String, dynamic> toLogMap() {
    return {
      'id': id,
      'scheduleId': scheduleId,
      'databaseName': databaseName,
      'backupType': backupType.name,
      'totalDurationMs': totalDuration?.inMilliseconds,
      'backupDurationMs': backupDuration?.inMilliseconds,
      'verifyDurationMs': verifyDuration?.inMilliseconds,
      'throughputMbps': throughputMbps,
      'fileSizeBytes': fileSizeBytes,
      'fileSizeFormatted': fileSizeBytes != null ? _formatBytes(fileSizeBytes!) : null,
      'enableChecksum': enableChecksum,
      'compressionEnabled': compressionEnabled,
      'failureReason': failureReason?.name,
      'errorMessage': errorMessage,
      'createdAt': createdAt.toIso8601String(),
      'success': isSuccess,
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
