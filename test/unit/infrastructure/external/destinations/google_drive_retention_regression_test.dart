import 'dart:convert';

import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_auth_client.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_folder_ops.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_retention.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _AuthService extends Mock implements GoogleAuthService {}

class _Client extends AuthenticatedHttpClient {
  _Client(this.inner) : super('test');
  final http.Client inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(request);
  @override
  void close() {
    inner.close();
    super.close();
  }
}

class _Auth extends GoogleDriveAuthClient {
  _Auth(this.client) : super(_AuthService());
  final _Client client;
  @override
  Future<rd.Result<GoogleDriveClientSession>> getAuthenticatedClient() async =>
      rd.Success(GoogleDriveClientSession(client: client, accessToken: 'test'));
  @override
  Future<T> executeWithTokenRefresh<T>(Future<T> Function() operation) =>
      operation();
}

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  for (final scenario in [
    'protected',
    'later-folder',
    'invalid-date',
    'incomplete',
    'page-error',
    'delete-error',
    'repeated-token',
  ]) {
    test('should preserve retention safety when $scenario', () async {
      final deleted = <String>[];
      final client = _Client(
        MockClient((request) async {
          if (request.method == 'DELETE') {
            deleted.add(request.url.pathSegments.last);
            return scenario == 'delete-error'
                ? _json({
                    'error': {'code': 403, 'message': 'denied'},
                  }, 403)
                : http.Response('', 204);
          }
          final query = request.url.queryParameters['q']!;
          final token = request.url.queryParameters['pageToken'];
          expect(
            request.url.queryParameters['fields'],
            contains('nextPageToken'),
          );
          if (query.contains('name =')) {
            return _json({
              'files': [
                {'id': 'main'},
              ],
            });
          }
          if (query.contains("'main' in parents")) {
            if (scenario == 'later-folder' && token == null) {
              return _json({'files': <Object>[], 'nextPageToken': 'folders-2'});
            }
            return _json({
              'files': [
                {
                  'id': 'old',
                  'name': scenario == 'invalid-date'
                      ? '2000-01-01-copy'
                      : '2000-01-01',
                },
                if (scenario == 'invalid-date')
                  {'id': 'invalid', 'name': '2000-02-31'},
              ],
            });
          }
          if (scenario == 'incomplete') {
            return _json({'files': <Object>[], 'incompleteSearch': true});
          }
          if (scenario == 'repeated-token') {
            return _json({'files': <Object>[], 'nextPageToken': 'same'});
          }
          if ((scenario == 'protected' || scenario == 'page-error') &&
              token == null) {
            return _json({'files': <Object>[], 'nextPageToken': 'children-2'});
          }
          if (scenario == 'page-error') {
            return _json({
              'error': {'code': 503, 'message': 'unavailable'},
            }, 503);
          }
          return _json({
            'files': [
              if (scenario == 'protected') {'name': 'backup_b12345678.bak'},
            ],
          });
        }),
      );
      addTearDown(client.close);
      final auth = _Auth(client);
      final result =
          await GoogleDriveRetention(
            auth,
            GoogleDriveFolderOps(auth),
          ).cleanOldBackups(
            config: const GoogleDriveDestinationConfig(
              folderId: 'root',
              folderName: 'Backups',
              accessToken: '',
              refreshToken: '',
              protectedBackupIdShortPrefixes: {'12345678'},
            ),
          );
      final fails = [
        'incomplete',
        'page-error',
        'delete-error',
        'repeated-token',
      ].contains(scenario);
      expect(result.isError(), fails);
      expect(
        deleted,
        ['later-folder', 'delete-error'].contains(scenario) ? ['old'] : isEmpty,
      );
      if (!fails) {
        expect(result.getOrNull(), scenario == 'later-folder' ? 1 : 0);
      }
    });
  }

  test('should list backups across an empty intermediate page', () async {
    final client = _Client(
      MockClient((request) async {
        return _json(
          request.url.queryParameters['pageToken'] == null
              ? {'files': <Object>[], 'nextPageToken': 'next'}
              : {
                  'files': [
                    {'id': 'backup', 'name': 'backup.bak'},
                  ],
                },
        );
      }),
    );
    addTearDown(client.close);
    final result = await GoogleDriveFolderOps(_Auth(client))
        .listBackups(folderId: 'main');
    expect(result.getOrThrow().single.id, 'backup');
  });
}
