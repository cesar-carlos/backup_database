import 'dart:io';

import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/nextcloud_failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_folder_ops.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_http_client.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_integrity_verifier.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_uploader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart';

class _Http extends Mock implements NextcloudHttpClient {}

class _Folders extends Mock implements NextcloudFolderOps {}

class _Integrity extends Mock implements NextcloudIntegrityVerifier {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uri.parse('https://example.test/file')));
  for (final code in [
    FailureCodes.integrityValidationFailed,
    FailureCodes.integrityValidationInconclusive,
  ]) {
    test('should delete only proven corruption, validation=$code', () async {
      final dir = await Directory.systemTemp.createTemp('nextcloud-integrity-');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File('${dir.path}/backup').writeAsBytes([1, 2, 3]);
      EncryptionService.initializeWithDeviceKey('test-nextcloud');
      addTearDown(EncryptionService.resetToLegacy);
      final config = NextcloudDestinationConfig(
        serverUrl: 'https://example.test',
        username: 'user',
        appPassword: EncryptionService.encrypt('password'),
      );
      final dio = Dio();
      var deletes = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'DELETE') deletes++;
            handler.resolve(Response(requestOptions: options, statusCode: 201));
          },
        ),
      );
      final http = _Http();
      when(() => http.create(config: config, password: 'password'))
          .thenReturn(dio);
      final folders = _Folders();
      when(
        () => folders.ensureFolderExists(
          dio: dio,
          config: config,
          path: any(named: 'path'),
        ),
      ).thenAnswer((_) async {});
      final integrity = _Integrity();
      when(
        () => integrity.validateUploadedFile(
          dio: dio,
          uploadUrl: any(named: 'uploadUrl'),
          fileSize: 3,
          localSha256: any(named: 'localSha256'),
          enableStrongIntegrityValidation: false,
          enableReadBackValidation: false,
        ),
      ).thenAnswer(
        (_) async =>
            Failure(NextcloudFailure(message: 'validation failed', code: code)),
      );
      final result = await NextcloudUploader(
        http,
        folders,
        integrity,
      ).upload(sourceFilePath: file.path, config: config, maxRetries: 1);
      expect(result.isError(), isTrue);
      expect(deletes, code == FailureCodes.integrityValidationFailed ? 1 : 0);
      await expectLater(
        dio.get('https://example.test'),
        throwsA(isA<DioException>()),
      );
    });
  }
}
