import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/services/upload_progress_callback.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_upload_recovery.dart';
import 'package:backup_database/infrastructure/external/upload_session_store.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleDrivePersistentUpload {
  GoogleDrivePersistentUpload(this.store);
  final UploadSessionStore store;
  static const int chunkSize = 1024 * 1024;

  Future<drive.File> upload({
    required http.Client client,
    required drive.DriveApi api,
    required File file,
    required String accountId,
    required String parentId,
    required String name,
    required int size,
    required String md5,
    bool Function()? isCancelled,
    UploadProgressCallback? onProgress,
  }) => store.run(
    ['drive', accountId, parentId, name, size, md5],
    (
      checkpoint,
    ) async {
      UploadCancellation.throwIfCancelled(isCancelled);
      var state = await checkpoint.read();
      if (state != null &&
          (state['id'] is! String ||
              (state['id'] as String).isEmpty ||
              (state.containsKey('uri') &&
                  (state['uri'] is! String ||
                      (state['uri'] as String).isEmpty)))) {
        throw const FormatException('Checkpoint Google Drive inválido.');
      }
      final completed = state != null
          ? null
          : await findCompletedGoogleDriveUpload(
              api,
              parentId: parentId,
              fileName: name,
              fileSize: size,
              md5: md5,
            );
      UploadCancellation.throwIfCancelled(isCancelled);
      if (completed != null) {
        await checkpoint.clear();
        return completed;
      }
      if (state == null) {
        final ids = await api.files.generateIds(count: 1, space: 'drive');
        if (ids.ids?.length != 1) throw StateError('ID Google Drive ausente.');
        state = {'id': ids.ids!.single};
        await checkpoint.save(state);
      }
      final id = state['id'] as String;
      if (id.isEmpty) throw StateError('ID Google Drive inválido.');

      Future<drive.File> complete(drive.File result) async {
        UploadCancellation.throwIfCancelled(isCancelled);
        if (result.id != id ||
            int.tryParse(result.size ?? '') != size ||
            result.md5Checksum?.toLowerCase() != md5.toLowerCase()) {
          throw StateError('Integridade Google Drive não confirmada.');
        }
        await checkpoint.clear();
        return result;
      }

      Future<http.Response> request(
        String method,
        Uri uri,
        Map<String, String> headers,
        List<int> body,
      ) async {
        UploadCancellation.throwIfCancelled(isCancelled);
        final req = http.Request(method, uri)
          ..followRedirects = false
          ..headers.addAll(headers)
          ..bodyBytes = body;
        late final http.Response response;
        try {
          response = await http.Response.fromStream(await client.send(req));
        } on http.ClientException {
          // Session URLs are bearer capabilities and must not reach error logs.
          throw const SocketException(
            'Conexão interrompida no envio Google Drive.',
          );
        }
        UploadCancellation.throwIfCancelled(isCancelled);
        return response;
      }

      Uri sessionUri(String value) {
        final uri = Uri.parse(value);
        if (uri.scheme != 'https' ||
            uri.host != 'www.googleapis.com' ||
            uri.port != 443 ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment ||
            !uri.path.startsWith('/upload/drive/v3/files')) {
          throw StateError('Endereço de sessão Google Drive inválido.');
        }
        return uri;
      }

      int received(http.Response response) {
        final range = response.headers['range'];
        if (range == null) return 0;
        final match = RegExp(r'^bytes=0-(\d+)$').firstMatch(range);
        final end = match == null ? null : int.tryParse(match.group(1)!);
        if (end == null || end < 0 || end >= size) {
          throw StateError('Offset Google Drive inválido.');
        }
        return end + 1;
      }

      drive.File metadata(http.Response response) => drive.File.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      void check(http.Response response, Set<int> allowed) {
        if (!allowed.contains(response.statusCode)) {
          throw drive.DetailedApiRequestError(
            response.statusCode,
            'Falha no envio resumível Google Drive.',
          );
        }
      }

      var uri = state['uri'] is String
          ? sessionUri(state['uri'] as String)
          : null;
      var offset = 0;
      if (uri != null) {
        final status = await request('PUT', uri, {
          'Content-Range': 'bytes */$size',
        }, []);
        if (status.statusCode == 200 || status.statusCode == 201) {
          return complete(metadata(status));
        }
        if (status.statusCode == 404 || status.statusCode == 410) {
          uri = null;
          state.remove('uri');
          await checkpoint.save(state);
        } else {
          check(status, {308});
          offset = received(status);
        }
      }
      if (uri == null) {
        final response = await request(
          'POST',
          Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
            'uploadType': 'resumable',
            'fields': 'id,name,size,md5Checksum',
          }),
          {
            'Content-Type': 'application/json; charset=utf-8',
            'X-Upload-Content-Length': '$size',
            'X-Upload-Content-Type': 'application/octet-stream',
          },
          utf8.encode(
            jsonEncode({
              'id': id,
              'name': name,
              'parents': [parentId],
            }),
          ),
        );
        if (response.statusCode == 409) {
          return complete(
            await api.files.get(id, $fields: 'id,name,size,md5Checksum')
                as drive.File,
          );
        }
        check(response, {200, 201});
        uri = sessionUri(response.headers['location'] ?? '');
        state['uri'] = uri.toString();
        await checkpoint.save(state);
      }
      final input = await file.open();
      try {
        while (offset < size) {
          UploadCancellation.throwIfCancelled(isCancelled);
          await input.setPosition(offset);
          final length = (size - offset).clamp(0, chunkSize);
          final bytes = Uint8List(length);
          var count = 0;
          while (count < length) {
            final read = await input.readInto(bytes, count, length);
            if (read == 0) throw StateError('Arquivo de origem foi alterado.');
            count += read;
          }
          final response = await request('PUT', uri, {
            'Content-Type': 'application/octet-stream',
            'Content-Range': 'bytes $offset-${offset + length - 1}/$size',
          }, bytes);
          if (response.statusCode == 200 || response.statusCode == 201) {
            return await complete(metadata(response));
          }
          check(response, {308});
          final next = received(response);
          if (next <= offset || next > offset + length) {
            throw StateError('Offset Google Drive sem progresso.');
          }
          offset = next;
          onProgress?.call(offset / size);
        }
        final response = await request('PUT', uri, {
          'Content-Range': 'bytes */$size',
        }, []);
        check(response, {200, 201});
        return await complete(metadata(response));
      } finally {
        await input.close();
      }
    },
    resourceIdentity: ['drive', accountId, parentId, name],
    isCancelled: isCancelled,
  );
}
