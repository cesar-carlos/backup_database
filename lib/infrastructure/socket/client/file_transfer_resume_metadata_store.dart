import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';

class FileTransferResumeMetadata {
  const FileTransferResumeMetadata({
    required this.filePath,
    required this.partFilePath,
    required this.chunkSize,
    required this.updatedAt,
    this.expectedSize,
    this.expectedHash,
    this.isCompressed = false,
    this.scheduleId,
    this.runId,
  });

  final String filePath;
  final String partFilePath;
  final int chunkSize;
  final int? expectedSize;
  final String? expectedHash;
  final bool isCompressed;
  final String? scheduleId;

  /// PR-6: `runId` da execucao remota que originou o artefato. Resume
  /// valida que o `runId` solicitado bate com o salvo — se diferente,
  /// descarta a metadata e forca download do zero (evita reaproveitar
  /// chunk parcial de outra execucao com mesmo hash de path).
  final String? runId;

  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'filePath': filePath,
    'partFilePath': partFilePath,
    'chunkSize': chunkSize,
    'expectedSize': expectedSize,
    'expectedHash': expectedHash,
    'isCompressed': isCompressed,
    'scheduleId': scheduleId,
    if (runId != null) 'runId': runId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory FileTransferResumeMetadata.fromJson(Map<String, Object?> json) {
    final rawUpdatedAt = json['updatedAt'] as String? ?? '';
    final updatedAt =
        DateTime.tryParse(rawUpdatedAt)?.toUtc() ?? DateTime.now().toUtc();
    final rawExpectedSize = json['expectedSize'];

    return FileTransferResumeMetadata(
      filePath: json['filePath'] as String? ?? '',
      partFilePath: json['partFilePath'] as String? ?? '',
      chunkSize: json['chunkSize'] as int? ?? 0,
      expectedSize: rawExpectedSize is int ? rawExpectedSize : null,
      expectedHash: json['expectedHash'] as String?,
      isCompressed: json['isCompressed'] as bool? ?? false,
      scheduleId: json['scheduleId'] as String?,
      runId: json['runId'] as String?,
      updatedAt: updatedAt,
    );
  }

  /// PR-6: helper para o `ConnectionManager` decidir se reaproveita
  /// esta metadata em resume. Quando ambos `runId`s estao presentes e
  /// sao diferentes, a metadata pertence a outra execucao e nao deve
  /// ser usada (forca download do zero).
  bool matchesRunId(String? requestedRunId) {
    if (runId == null || runId!.isEmpty) return true;
    if (requestedRunId == null || requestedRunId.isEmpty) return true;
    return runId == requestedRunId;
  }
}

class FileTransferResumeMetadataStore {
  const FileTransferResumeMetadataStore();

  Future<FileTransferResumeMetadata?> read(String outputPath) async {
    final metadataFile = File(_metadataPath(outputPath));
    if (!await metadataFile.exists()) {
      return null;
    }

    try {
      final content = await metadataFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return FileTransferResumeMetadata.fromJson(
        decoded.cast<String, Object?>(),
      );
    } on Object catch (e) {
      LoggerService.warning(
        '[ResumeMetadataStore] Falha ao ler metadata de resume: $e',
      );
      return null;
    }
  }

  Future<void> write(
    String outputPath,
    FileTransferResumeMetadata metadata,
  ) async {
    final metadataFile = File(_metadataPath(outputPath));
    if (!await metadataFile.parent.exists()) {
      await metadataFile.parent.create(recursive: true);
    }
    final payload = jsonEncode(metadata.toJson());
    await metadataFile.writeAsString(payload, flush: true);
  }

  Future<void> delete(String outputPath) async {
    final metadataFile = File(_metadataPath(outputPath));
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
  }

  String _metadataPath(String outputPath) => '$outputPath.part.meta.json';
}
