import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_resumable_uploader.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_simple_uploader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions, Stream<Uint8List>?)
  respond;
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options, requestStream);

  @override
  void close({bool force = false}) => closed = true;
}

ResponseBody _json(Map<String, Object> value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  late Directory temp;
  late File file;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dropbox_upload_');
    file = await File('${temp.path}/backup').writeAsBytes([1, 2, 3, 4]);
  });
  tearDown(() => temp.delete(recursive: true));

  for (final mode in [
    'not-received',
    'received',
    'invalid-offset',
    'partial',
    'rewind',
    'permanent',
    'cancel-retry',
  ]) {
    test(
      'should recover an interrupted Dropbox append safely: $mode',
      () async {
        const chunk = 4 * 1024 * 1024;
        await file.writeAsBytes(Uint8List(chunk * 2 + 1));
        var cancelled = false;
        var starts = 0;
        var appends = 0;
        var finishes = 0;
        final adapter = _Adapter((request, stream) async {
          final sentBytes =
              await stream?.fold<int>(
                0,
                (count, bytes) => count + bytes.length,
              ) ??
              0;
          final args = jsonDecode(
            request.headers['Dropbox-API-Arg'] as String,
          ) as Map<String, dynamic>;
          if (request.path.endsWith('/start')) {
            starts++;
            return _json({'session_id': 'same-session'});
          }
          expect((args['cursor'] as Map)['session_id'], 'same-session');
          if (request.path.endsWith('/append_v2')) {
            appends++;
            final resumed = mode == 'partial' && appends == 3;
            expect(
              (args['cursor'] as Map)['offset'],
              resumed ? chunk + 17 : chunk,
            );
            expect(sentBytes, resumed ? chunk - 17 : chunk);
            if (resumed) return _json({});
            if (appends == 1 || mode == 'permanent') {
              if (mode == 'cancel-retry') cancelled = true;
              throw DioException(
                requestOptions: request,
                type: DioExceptionType.connectionError,
              );
            }
            if (mode != 'not-received') {
              return ResponseBody.fromString(
                jsonEncode({
                  'error': {
                    '.tag': 'incorrect_offset',
                    'correct_offset': mode == 'received'
                        ? chunk * 2
                        : mode == 'partial'
                        ? chunk + 17
                        : mode == 'rewind'
                        ? chunk - 1
                        : chunk * 2 + 1,
                  },
                }),
                409,
                headers: {
                  Headers.contentTypeHeader: [Headers.jsonContentType],
                },
              );
            }
            return _json({});
          }
          finishes++;
          expect((args['cursor'] as Map)['offset'], chunk * 2);
          return _json({'id': 'finished', 'size': chunk * 2 + 1});
        });
        final auth = Dio();
        addTearDown(() => auth.close(force: true));
        final work =
            DropboxResumableUploader(
              contentClientFactory: (options) =>
                  Dio(options)..httpClientAdapter = adapter,
            ).upload(
              dio: auth,
              sourceFile: file,
              filePath: '/backup',
              fileSize: chunk * 2 + 1,
              isCancelled: () => cancelled,
            );
        if (mode == 'cancel-retry') {
          await expectLater(
            work,
            throwsA(predicate<Object>(UploadCancellation.isCancellation)),
          );
          expect(finishes, 0);
        } else if (['invalid-offset', 'rewind', 'permanent'].contains(mode)) {
          await expectLater(work, throwsA(isA<DioException>()));
          expect(finishes, 0);
        } else {
          expect((await work)['id'], 'finished');
          expect(finishes, 1);
        }
        expect(starts, 1);
        expect(
          appends,
          mode == 'partial' || mode == 'permanent'
              ? 3
              : mode == 'cancel-retry'
              ? 1
              : 2,
        );
        expect(adapter.closed, isTrue);
      },
    );
  }

  for (final resumable in [false, true]) {
    test(
      'should cancel a pending response without waiting for the server, resumable=$resumable',
      () async {
        var cancelled = false;
        final entered = Completer<void>();
        final release = Completer<void>();
        final adapter = _Adapter((request, stream) async {
          await stream?.drain<void>();
          entered.complete();
          await release.future;
          return _json({'session_id': 'late', 'id': 'late', 'size': 4});
        });
        Dio factory(BaseOptions options) =>
            Dio(options)..httpClientAdapter = adapter;
        final authDio = Dio();
        addTearDown(() => authDio.close(force: true));
        final work = resumable
            ? DropboxResumableUploader(contentClientFactory: factory).upload(
                dio: authDio,
                sourceFile: file,
                filePath: '/backup',
                fileSize: 4,
                isCancelled: () => cancelled,
              )
            : DropboxSimpleUploader(contentClientFactory: factory).upload(
                dio: authDio,
                sourceFile: file,
                filePath: '/backup',
                isCancelled: () => cancelled,
              );
        final expectation = expectLater(
          work.timeout(const Duration(seconds: 2)),
          throwsA(
            predicate<Object>(UploadCancellation.isCancellation),
          ),
        );
        await entered.future;
        cancelled = true;
        try {
          await expectation;
          expect(adapter.closed, isTrue);
        } finally {
          release.complete();
        }
      },
    );
    test(
      'retry after lost response keeps same path, resumable=$resumable',
      () async {
        final commits = <Map<String, dynamic>>[];
        final adapters = <_Adapter>[];
        var loseResponse = true;
        const path = '/cópia/"backup"-😀.bak';
        Dio factory(BaseOptions options) {
          final adapter = _Adapter((request, stream) async {
            await stream?.drain<void>();
            final header = request.headers['Dropbox-API-Arg'] as String;
            expect(header.codeUnits.every((unit) => unit < 127), isTrue);
            final args = jsonDecode(header) as Map<String, dynamic>;
            if (request.path.endsWith('/start')) {
              return _json({'session_id': 'session'});
            }
            final commit = resumable
                ? args['commit'] as Map<String, dynamic>
                : args;
            commits.add(commit);
            if (loseResponse) {
              loseResponse = false;
              throw DioException(
                requestOptions: request,
                type: DioExceptionType.connectionError,
              );
            }
            return _json({'id': 'same-file', 'size': 4});
          });
          adapters.add(adapter);
          return Dio(options)..httpClientAdapter = adapter;
        }

        Future<Map<String, dynamic>> upload() => resumable
            ? DropboxResumableUploader(contentClientFactory: factory).upload(
                dio: Dio(),
                sourceFile: file,
                filePath: path,
                fileSize: 4,
              )
            : DropboxSimpleUploader(contentClientFactory: factory).upload(
                dio: Dio(),
                sourceFile: file,
                filePath: path,
              );
        await expectLater(upload(), throwsA(isA<DioException>()));
        expect((await upload())['id'], 'same-file');
        expect(commits, hasLength(2));
        for (final commit in commits) {
          expect(commit['path'], path);
          expect(commit['mode'], 'overwrite');
          expect(commit['autorename'], isFalse);
        }
        expect(adapters.every((adapter) => adapter.closed), isTrue);
      },
    );
  }

  test('cancellation after session start prevents finish', () async {
    var cancelled = false;
    final calls = <String>[];
    final adapter = _Adapter((request, stream) async {
      await stream?.drain<void>();
      calls.add(request.path);
      cancelled = true;
      return _json({'session_id': 'session'});
    });
    await expectLater(
      DropboxResumableUploader(
        contentClientFactory: (options) =>
            Dio(options)..httpClientAdapter = adapter,
      ).upload(
        dio: Dio(),
        sourceFile: file,
        filePath: '/backup',
        fileSize: 4,
        isCancelled: () => cancelled,
      ),
      throwsA(isA<UploadCancelledException>()),
    );
    expect(calls, ['/2/files/upload_session/start']);
    expect(adapter.closed, isTrue);
  });

  test('simple upload checks cancellation while reading the body', () async {
    var cancelled = false;
    var completed = false;
    final adapter = _Adapter((request, stream) async {
      cancelled = true;
      await stream!.drain<void>();
      completed = true;
      return _json({'id': 'unexpected'});
    });
    await expectLater(
      DropboxSimpleUploader(
        contentClientFactory: (options) =>
            Dio(options)..httpClientAdapter = adapter,
      ).upload(
        dio: Dio(),
        sourceFile: file,
        filePath: '/backup',
        isCancelled: () => cancelled,
      ),
      throwsA(predicate<Object>(UploadCancellation.isCancellation)),
    );
    expect(completed, isFalse);
    expect(adapter.closed, isTrue);
  });

  test('source truncated before resumable upload never commits', () async {
    final adapter = _Adapter((request, stream) async {
      fail('A truncated source must not be committed');
    });
    await expectLater(
      DropboxResumableUploader(
        contentClientFactory: (options) =>
            Dio(options)..httpClientAdapter = adapter,
      ).upload(dio: Dio(), sourceFile: file, filePath: '/backup', fileSize: 8),
      throwsStateError,
    );
    expect(adapter.closed, isTrue);
  });
}
