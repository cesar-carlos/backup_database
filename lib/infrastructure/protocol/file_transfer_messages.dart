import 'dart:convert';

import 'package:backup_database/domain/entities/remote_file_entry.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/file_chunker.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

Message createListFilesMessage({required int requestId}) {
  const payload = <String, dynamic>{};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.listFiles,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createFileListMessage({
  required int requestId,
  required List<RemoteFileEntry> files,
  String? error,
  ErrorCode? errorCode,
}) {
  final payload = <String, dynamic>{
    'files': files.map(_remoteFileEntryToMap).toList(),
    ...? (error != null ? {'error': error} : null),
    ...? (errorCode != null ? {'errorCode': errorCode.code} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.fileList,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Map<String, dynamic> _remoteFileEntryToMap(RemoteFileEntry e) => {
      'path': e.path,
      'size': e.size,
      'lastModified': e.lastModified.toIso8601String(),
    };

Message createFileTransferStartRequestMessage({
  required int requestId,
  required String filePath,
  String? scheduleId,
}) {
  final payload = <String, dynamic>{
    'filePath': filePath,
    ...? (scheduleId != null ? {'scheduleId': scheduleId} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.fileTransferStart,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createFileTransferStartMetadataMessage({
  required int requestId,
  required String fileName,
  required int fileSize,
  required int totalChunks,
}) {
  final payload = <String, dynamic>{
    'fileName': fileName,
    'fileSize': fileSize,
    'totalChunks': totalChunks,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.fileTransferStart,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createFileChunkMessage({
  required int requestId,
  required FileChunk chunk,
}) {
  final payload = chunk.toJson();
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.fileChunk,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createFileTransferProgressMessage({
  required int requestId,
  required int currentChunk,
  required int totalChunks,
}) {
  final payload = <String, dynamic>{
    'currentChunk': currentChunk,
    'totalChunks': totalChunks,
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.fileTransferProgress,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createFileTransferCompleteMessage({
  required int requestId,
  int? checksum,
}) {
  final payload = <String, dynamic>{
    ...? (checksum != null ? {'checksum': checksum} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.fileTransferComplete,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createFileTransferErrorMessage({
  required int requestId,
  required String errorMessage,
  ErrorCode? errorCode,
}) {
  final payload = <String, dynamic>{
    'error': errorMessage,
    ...? (errorCode != null ? {'errorCode': errorCode.code} : null),
  };
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.fileTransferError,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

Message createFileAckMessage({
  required int requestId,
  required int chunkIndex,
}) {
  final payload = <String, dynamic>{'chunkIndex': chunkIndex};
  final payloadJson = jsonEncode(payload);
  final length = utf8.encode(payloadJson).length;
  return Message(
    header: MessageHeader(
      type: MessageType.fileAck,
      length: length,
      requestId: requestId,
    ),
    payload: payload,
    checksum: 0,
  );
}

bool isListFilesRequest(Message message) =>
    message.header.type == MessageType.listFiles;

bool isFileListMessage(Message message) =>
    message.header.type == MessageType.fileList;

List<RemoteFileEntry> getFileListFromPayload(Message message) {
  final list = message.payload['files'];
  if (list is! List) return [];
  final result = <RemoteFileEntry>[];
  for (final item in list) {
    if (item is! Map<String, dynamic>) continue;
    final path = item['path'] as String? ?? '';
    final size = item['size'] as int? ?? 0;
    final lastModifiedStr = item['lastModified'] as String?;
    final lastModified = lastModifiedStr != null
        ? DateTime.tryParse(lastModifiedStr) ?? DateTime.now()
        : DateTime.now();
    result.add(RemoteFileEntry(
      path: path,
      size: size,
      lastModified: lastModified,
    ));
  }
  return result;
}

bool isFileTransferStartRequest(Message message) {
  if (message.header.type != MessageType.fileTransferStart) return false;
  return message.payload.containsKey('filePath');
}

bool isFileTransferStartMetadata(Message message) {
  if (message.header.type != MessageType.fileTransferStart) return false;
  return message.payload.containsKey('fileName') &&
      message.payload.containsKey('fileSize') &&
      message.payload.containsKey('totalChunks');
}

bool isFileChunkMessage(Message message) =>
    message.header.type == MessageType.fileChunk;

bool isFileTransferProgressMessage(Message message) =>
    message.header.type == MessageType.fileTransferProgress;

bool isFileTransferCompleteMessage(Message message) =>
    message.header.type == MessageType.fileTransferComplete;

bool isFileTransferErrorMessage(Message message) =>
    message.header.type == MessageType.fileTransferError;

bool isFileAckMessage(Message message) =>
    message.header.type == MessageType.fileAck;

String getFilePathFromRequest(Message message) =>
    message.payload['filePath'] as String? ?? '';

String? getScheduleIdFromRequest(Message message) =>
    message.payload['scheduleId'] as String?;

String getFileNameFromMetadata(Message message) =>
    message.payload['fileName'] as String? ?? '';

int getFileSizeFromMetadata(Message message) =>
    message.payload['fileSize'] as int? ?? 0;

int getTotalChunksFromMetadata(Message message) =>
    message.payload['totalChunks'] as int? ?? 0;

FileChunk getFileChunkFromPayload(Message message) =>
    FileChunk.fromJson(Map<String, dynamic>.from(message.payload));

int getCurrentChunkFromProgress(Message message) =>
    message.payload['currentChunk'] as int? ?? 0;

int getTotalChunksFromProgress(Message message) =>
    message.payload['totalChunks'] as int? ?? 0;

int? getChecksumFromComplete(Message message) =>
    message.payload['checksum'] as int?;

String getErrorFromFileTransferError(Message message) =>
    message.payload['error'] as String? ?? '';

ErrorCode? getErrorCodeFromFileTransferError(Message message) {
  final code = message.payload['errorCode'] as String?;
  return code != null ? ErrorCode.fromString(code) : null;
}

int getChunkIndexFromAck(Message message) =>
    message.payload['chunkIndex'] as int? ?? 0;

String? getErrorFromFileList(Message message) =>
    message.payload['error'] as String?;

ErrorCode? getErrorCodeFromFileList(Message message) {
  final code = message.payload['errorCode'] as String?;
  return code != null ? ErrorCode.fromString(code) : null;
}
