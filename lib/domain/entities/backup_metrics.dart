import 'dart:convert';

class BackupMetrics {
  const BackupMetrics({
    required this.totalDuration,
    required this.backupDuration,
    required this.verifyDuration,
    required this.backupSizeBytes,
    required this.backupSpeedMbPerSec,
    required this.backupType,
    required this.flags,
    this.compressionDuration = Duration.zero,
    this.uploadDuration = Duration.zero,
    this.cleanupDuration = Duration.zero,
    this.sybaseOptions,
  });

  final Duration totalDuration;
  final Duration backupDuration;
  final Duration verifyDuration;
  final int backupSizeBytes;
  final double backupSpeedMbPerSec;
  final String backupType;
  final BackupFlags flags;
  final Duration compressionDuration;
  final Duration uploadDuration;
  final Duration cleanupDuration;
  final Map<String, dynamic>? sybaseOptions;

  BackupMetrics copyWith({
    Duration? totalDuration,
    Duration? backupDuration,
    Duration? verifyDuration,
    int? backupSizeBytes,
    double? backupSpeedMbPerSec,
    String? backupType,
    BackupFlags? flags,
    Duration? compressionDuration,
    Duration? uploadDuration,
    Duration? cleanupDuration,
    Map<String, dynamic>? sybaseOptions,
  }) {
    return BackupMetrics(
      totalDuration: totalDuration ?? this.totalDuration,
      backupDuration: backupDuration ?? this.backupDuration,
      verifyDuration: verifyDuration ?? this.verifyDuration,
      backupSizeBytes: backupSizeBytes ?? this.backupSizeBytes,
      backupSpeedMbPerSec: backupSpeedMbPerSec ?? this.backupSpeedMbPerSec,
      backupType: backupType ?? this.backupType,
      flags: flags ?? this.flags,
      compressionDuration: compressionDuration ?? this.compressionDuration,
      uploadDuration: uploadDuration ?? this.uploadDuration,
      cleanupDuration: cleanupDuration ?? this.cleanupDuration,
      sybaseOptions: sybaseOptions ?? this.sybaseOptions,
    );
  }

  Map<String, dynamic> toJson() => {
    'totalDurationMs': totalDuration.inMilliseconds,
    'backupDurationMs': backupDuration.inMilliseconds,
    'verifyDurationMs': verifyDuration.inMilliseconds,
    'compressionDurationMs': compressionDuration.inMilliseconds,
    'uploadDurationMs': uploadDuration.inMilliseconds,
    'cleanupDurationMs': cleanupDuration.inMilliseconds,
    'backupSizeBytes': backupSizeBytes,
    'backupSpeedMbPerSec': backupSpeedMbPerSec,
    'backupType': backupType,
    'flags': {
      'compression': flags.compression,
      'verifyPolicy': flags.verifyPolicy,
      'stripingCount': flags.stripingCount,
      'withChecksum': flags.withChecksum,
      'stopOnError': flags.stopOnError,
    },
    if (sybaseOptions != null && sybaseOptions!.isNotEmpty)
      'sybaseOptions': sybaseOptions,
  };

  static BackupMetrics? fromJson(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(
        (jsonDecode(jsonStr) as Map).map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      );
      final totalMs = map['totalDurationMs'] as int? ?? 0;
      final backupMs = map['backupDurationMs'] as int? ?? totalMs;
      final verifyMs = map['verifyDurationMs'] as int? ?? 0;
      final compressionMs = map['compressionDurationMs'] as int? ?? 0;
      final uploadMs = map['uploadDurationMs'] as int? ?? 0;
      final cleanupMs = map['cleanupDurationMs'] as int? ?? 0;
      final flagsMap = map['flags'] as Map?;
      final flags = flagsMap != null
          ? BackupFlags(
              compression: flagsMap['compression'] as bool? ?? false,
              verifyPolicy: flagsMap['verifyPolicy'] as String? ?? 'none',
              stripingCount: flagsMap['stripingCount'] as int? ?? 1,
              withChecksum: flagsMap['withChecksum'] as bool? ?? false,
              stopOnError: flagsMap['stopOnError'] as bool? ?? true,
            )
          : const BackupFlags(
              compression: false,
              verifyPolicy: 'none',
              stripingCount: 1,
              withChecksum: false,
              stopOnError: true,
            );
      final sybaseOptionsMap = map['sybaseOptions'] as Map?;
      final sybaseOptions = sybaseOptionsMap != null
          ? Map<String, dynamic>.from(
              sybaseOptionsMap.map(
                (k, v) => MapEntry(k.toString(), v),
              ),
            )
          : null;

      return BackupMetrics(
        totalDuration: Duration(milliseconds: totalMs),
        backupDuration: Duration(milliseconds: backupMs),
        verifyDuration: Duration(milliseconds: verifyMs),
        compressionDuration: Duration(milliseconds: compressionMs),
        uploadDuration: Duration(milliseconds: uploadMs),
        cleanupDuration: Duration(milliseconds: cleanupMs),
        backupSizeBytes: map['backupSizeBytes'] as int? ?? 0,
        backupSpeedMbPerSec:
            (map['backupSpeedMbPerSec'] as num?)?.toDouble() ?? 0,
        backupType: map['backupType'] as String? ?? 'full',
        flags: flags,
        sybaseOptions: sybaseOptions,
      );
    } on Object {
      return null;
    }
  }

  String get backupSizeFormatted => _formatBytes(backupSizeBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class BackupFlags {
  const BackupFlags({
    required this.compression,
    required this.verifyPolicy,
    required this.stripingCount,
    required this.withChecksum,
    required this.stopOnError,
  });

  final bool compression;
  final String verifyPolicy;
  final int stripingCount;
  final bool withChecksum;
  final bool stopOnError;
}
