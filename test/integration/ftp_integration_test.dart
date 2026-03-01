import 'dart:io';

import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp_destination_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:path/path.dart' as p;

const _ftpTestPort = 21210;
const _ftpTestUser = 'ftp_test_user';
const _ftpTestPass = 'ftp_test_pass';

void main() {
  final runIntegration = Platform.environment['RUN_FTP_INTEGRATION'] == '1';

  group('FTP integration', () {
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
      skip: !runIntegration,
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
      skip: !runIntegration,
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
      skip: !runIntegration,
    );
  });
}
