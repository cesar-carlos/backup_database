import 'dart:io';

import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp_destination_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;

const _ftpTestPort = 21210;
const _ftpTestUser = 'ftp_test_user';
const _ftpTestPass = 'ftp_test_pass';

void main() {
  final runIntegration = Platform.environment['RUN_FTP_INTEGRATION'] == '1';
  final runRealIntegration =
      Platform.environment['RUN_FTP_REAL_INTEGRATION'] == '1';
  final runLocalIntegration = runIntegration && !runRealIntegration;

  final realHost = Platform.environment['FTP_IT_HOST'] ?? '';
  final realPort = int.tryParse(Platform.environment['FTP_IT_PORT'] ?? '21');
  final realUser = Platform.environment['FTP_IT_USER'] ?? '';
  final realPass = Platform.environment['FTP_IT_PASS'] ?? '';
  final realRemotePath = Platform.environment['FTP_IT_REMOTE_PATH'] ?? '';

  final hasRealConfig =
      realHost.isNotEmpty &&
      realPort != null &&
      realUser.isNotEmpty &&
      realPass.isNotEmpty &&
      realRemotePath.isNotEmpty;

  group('FTP integration (local in-process server)', () {
    late Directory serverRoot;
    late FtpServer ftpServer;
    late FtpDestinationService service;

    setUp(() async {
      serverRoot = await Directory.systemTemp.createTemp('ftp_integration_');
      final fileOps = PhysicalFileOperations(serverRoot.path);
      ftpServer = FtpServer(
        _ftpTestPort,
        username: _ftpTestUser,
        password: _ftpTestPass,
        fileOperations: fileOps,
        serverType: ServerType.readAndWrite,
      );
      await ftpServer.startInBackground();
      service = FtpDestinationService();
    });

    tearDown(() async {
      await ftpServer.stop();
      if (await serverRoot.exists()) {
        await serverRoot.delete(recursive: true);
      }
    });

    test(
      'upload completo sem falha - arquivo final aparece com nome correto',
      () async {
        final sourceDir = await Directory.systemTemp.createTemp('ftp_src_');
        addTearDown(() => sourceDir.delete(recursive: true));
        const content = 'Conteudo do backup de teste para FTP integration.';
        final sourceFile = File(p.join(sourceDir.path, 'backup_test.bak'));
        await sourceFile.writeAsString(content);

        const config = FtpDestinationConfig(
          host: '127.0.0.1',
          port: _ftpTestPort,
          username: _ftpTestUser,
          password: _ftpTestPass,
          remotePath: '/',
        );

        final result = await service.upload(
          sourceFilePath: sourceFile.path,
          config: config,
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (success) {
            expect(success.fileSize, content.length);
            expect(success.remotePath, isNotEmpty);
          },
          (_) => fail('Expected success'),
        );

        final finalFile = File(p.join(serverRoot.path, 'backup_test.bak'));
        expect(await finalFile.exists(), isTrue);
        expect(await finalFile.readAsString(), content);

        final partFile = File(p.join(serverRoot.path, 'backup_test.bak.part'));
        expect(await partFile.exists(), isFalse);
      },
      skip: !runLocalIntegration,
    );

    test(
      'servidor sem REST STREAM - fallback para upload completo',
      () async {
        final sourceDir = await Directory.systemTemp.createTemp('ftp_src_');
        addTearDown(() => sourceDir.delete(recursive: true));
        const content = 'Fallback test - servidor ftp_server nao suporta REST.';
        final sourceFile = File(p.join(sourceDir.path, 'fallback_test.bak'));
        await sourceFile.writeAsString(content);

        const config = FtpDestinationConfig(
          host: '127.0.0.1',
          port: _ftpTestPort,
          username: _ftpTestUser,
          password: _ftpTestPass,
          remotePath: '/',
        );

        final result = await service.upload(
          sourceFilePath: sourceFile.path,
          config: config,
        );

        expect(result.isSuccess(), isTrue);
        result.fold(
          (success) => expect(success.fileSize, content.length),
          (_) => fail('Expected success'),
        );

        final finalFile = File(p.join(serverRoot.path, 'fallback_test.bak'));
        expect(await finalFile.exists(), isTrue);
        expect(await finalFile.readAsString(), content);
      },
      skip: !runLocalIntegration,
    );

    test(
      'testConnection retorna sucesso com servidor rodando',
      () async {
        const config = FtpDestinationConfig(
          host: '127.0.0.1',
          port: _ftpTestPort,
          username: _ftpTestUser,
          password: _ftpTestPass,
          remotePath: '/',
        );

        final result = await service.testConnection(config);

        expect(result.isSuccess(), isTrue);
        result.fold(
          (success) {
            expect(success.connected, isTrue);
          },
          (_) => fail('Expected success'),
        );
      },
      skip: !runLocalIntegration,
    );
  });

  group('FTP integration (real server)', () {
    late FtpDestinationService service;
    final uploadedFiles = <String>{};
    final shouldSkipReal = !runRealIntegration || !hasRealConfig;
    const uploadMaxAttempts = 3;
    const uploadRetryDelay = Duration(seconds: 2);

    FtpDestinationConfig createConfig({
      String? passwordOverride,
      String? remotePathOverride,
      bool enableResume = true,
    }) {
      return FtpDestinationConfig(
        host: realHost,
        port: realPort ?? 21,
        username: realUser,
        password: passwordOverride ?? realPass,
        remotePath: remotePathOverride ?? realRemotePath,
        enableResume: enableResume,
      );
    }

    Future<File> createSourceFile({
      required String fileName,
      required String content,
    }) async {
      final sourceDir = await Directory.systemTemp.createTemp('ftp_real_src_');
      addTearDown(() => sourceDir.delete(recursive: true));
      final sourceFile = File(p.join(sourceDir.path, fileName));
      await sourceFile.writeAsString(content);
      return sourceFile;
    }

    Future<void> cleanupUploadedFiles() async {
      if (uploadedFiles.isEmpty || !hasRealConfig) {
        return;
      }

      final ftp = FTPConnect(
        realHost,
        port: realPort,
        user: realUser,
        pass: realPass,
      );

      try {
        final connected = await ftp.connect();
        if (!connected) {
          return;
        }
        if (realRemotePath != '/') {
          await ftp.changeDirectory(realRemotePath);
        }
        for (final fileName in uploadedFiles) {
          try {
            await ftp.deleteFile(fileName);
          } on Object catch (_) {}
        }
      } on Object catch (_) {
      } finally {
        try {
          await ftp.disconnect();
        } on Object catch (_) {}
      }
      uploadedFiles.clear();
    }

    bool isTransientNetworkFailure(Object failure) {
      final message = failure.toString().toLowerCase();
      return message.contains('timed out') ||
          message.contains('connection timed out') ||
          message.contains('socketexception') ||
          message.contains('could not connect') ||
          message.contains('tempo limite') ||
          message.contains('semaphore');
    }

    setUp(() {
      service = FtpDestinationService();
    });

    tearDown(() async {
      await cleanupUploadedFiles();
    });

    test(
      'testConnection retorna sucesso no FTP real',
      () async {
        final result = await service.testConnection(createConfig());
        expect(result.isSuccess(), isTrue);
        result.fold(
          (success) => expect(success.connected, isTrue),
          (_) => fail('Expected success'),
        );
      },
      skip: shouldSkipReal,
    );

    test(
      'upload completo no FTP real cria arquivo final',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'it_real_upload_$now.bak';
        final sourceFile = await createSourceFile(
          fileName: fileName,
          content: 'integration ftp real full upload',
        );

        var result = await service.upload(
          sourceFilePath: sourceFile.path,
          config: createConfig(),
        );
        for (var attempt = 2;
            attempt <= uploadMaxAttempts && !result.isSuccess();
            attempt++) {
          final shouldRetry = result.fold(
            (_) => false,
            isTransientNetworkFailure,
          );
          if (!shouldRetry) {
            break;
          }
          await Future<void>.delayed(uploadRetryDelay);
          result = await service.upload(
            sourceFilePath: sourceFile.path,
            config: createConfig(),
          );
        }

        expect(result.isSuccess(), isTrue);
        result.fold(
          (success) => expect(success.remotePath, contains(fileName)),
          (_) => fail('Expected success'),
        );

        uploadedFiles
          ..add(fileName)
          ..add('$fileName.sha256')
          ..add('$fileName.part');
      },
      skip: shouldSkipReal,
    );

    test(
      'upload com customFileName no FTP real funciona',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final customFileName = 'it_real_custom_$now.bak';
        final sourceFile = await createSourceFile(
          fileName: 'it_real_src_$now.bak',
          content: 'integration ftp real custom filename',
        );

        var result = await service.upload(
          sourceFilePath: sourceFile.path,
          customFileName: customFileName,
          config: createConfig(),
        );
        for (var attempt = 2;
            attempt <= uploadMaxAttempts && !result.isSuccess();
            attempt++) {
          final shouldRetry = result.fold(
            (_) => false,
            isTransientNetworkFailure,
          );
          if (!shouldRetry) {
            break;
          }
          await Future<void>.delayed(uploadRetryDelay);
          result = await service.upload(
            sourceFilePath: sourceFile.path,
            customFileName: customFileName,
            config: createConfig(),
          );
        }

        expect(result.isSuccess(), isTrue);
        result.fold(
          (success) => expect(success.remotePath, contains(customFileName)),
          (_) => fail('Expected success'),
        );

        uploadedFiles
          ..add(customFileName)
          ..add('$customFileName.sha256')
          ..add('$customFileName.part');
      },
      skip: shouldSkipReal,
    );

    test(
      'upload no FTP real com resume desabilitado conclui',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'it_real_no_resume_$now.bak';
        final sourceFile = await createSourceFile(
          fileName: fileName,
          content: 'integration ftp real no resume',
        );

        var result = await service.upload(
          sourceFilePath: sourceFile.path,
          config: createConfig(enableResume: false),
        );
        for (var attempt = 2;
            attempt <= uploadMaxAttempts && !result.isSuccess();
            attempt++) {
          final shouldRetry = result.fold(
            (_) => false,
            isTransientNetworkFailure,
          );
          if (!shouldRetry) {
            break;
          }
          await Future<void>.delayed(uploadRetryDelay);
          result = await service.upload(
            sourceFilePath: sourceFile.path,
            config: createConfig(enableResume: false),
          );
        }

        expect(result.isSuccess(), isTrue);
        uploadedFiles
          ..add(fileName)
          ..add('$fileName.sha256')
          ..add('$fileName.part');
      },
      skip: shouldSkipReal,
    );

    test(
      'testConnection com senha inválida retorna falha',
      () async {
        final result = await service.testConnection(
          createConfig(passwordOverride: 'invalid_password_for_test'),
        );
        expect(result.isSuccess(), isFalse);
      },
      skip: shouldSkipReal,
    );
  });
}
