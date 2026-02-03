import 'dart:io';

import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Mock do IFileTransferLockService para testes
class MockFileTransferLockService implements IFileTransferLockService {
  @override
  Future<bool> tryAcquireLock(String filePath) async => true;

  @override
  Future<void> releaseLock(String filePath) async {}

  @override
  Future<bool> isLocked(String filePath) async => false;

  @override
  Future<void> cleanupExpiredLocks({Duration maxAge = const Duration(minutes: 30)}) async {}
}


int _nextPort = 29600;

int getTestPort() {
  final port = _nextPort;
  _nextPort++;
  return port;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('File Transfer Integration', () {
    test('Server sends file → Client receives and assembles correctly', () async {
      final serverDir = await Directory.systemTemp.createTemp('ft_server_');
      addTearDown(() => serverDir.delete(recursive: true));

      final testFile = File(p.join(serverDir.path, 'test.bin'));
      const content = 'Hello file transfer integration test!';
      await testFile.writeAsString(content);

      final mockLockService = MockFileTransferLockService();
      final fileTransferHandler = FileTransferMessageHandler(
        allowedBasePath: serverDir.path,
        lockService: mockLockService,
      );
      final server = TcpSocketServer(fileTransferHandler: fileTransferHandler);
      final port = getTestPort();
      await server.start(port: port);
      addTearDown(server.stop);
      addTearDown(() => Future<void>.delayed(const Duration(milliseconds: 200)));

      final connectionManager = ConnectionManager();
      addTearDown(connectionManager.disconnect);

      await connectionManager.connect(
        host: '127.0.0.1',
        port: port,
      );
      expect(connectionManager.isConnected, isTrue);

      final clientDir = await Directory.systemTemp.createTemp('ft_client_');
      addTearDown(() => clientDir.delete(recursive: true));
      final outputPath = p.join(clientDir.path, 'received.bin');

      final serverFilePath = p.normalize(p.join(serverDir.path, 'test.bin'));
      final result = await connectionManager.requestFile(
        filePath: serverFilePath,
        outputPath: outputPath,
      );

      expect(result.isSuccess(), isTrue);
      final outputFile = File(outputPath);
      expect(await outputFile.exists(), isTrue);
      expect(await outputFile.readAsString(), content);
    });

    test('Server returns error when path not allowed', () async {
      final serverDir = await Directory.systemTemp.createTemp('ft_server_');
      addTearDown(() => serverDir.delete(recursive: true));

      final mockLockService = MockFileTransferLockService();
      final fileTransferHandler = FileTransferMessageHandler(
        allowedBasePath: serverDir.path,
        lockService: mockLockService,
      );
      final server = TcpSocketServer(fileTransferHandler: fileTransferHandler);
      final port = getTestPort();
      await server.start(port: port);
      addTearDown(server.stop);
      addTearDown(() => Future<void>.delayed(const Duration(milliseconds: 200)));

      final connectionManager = ConnectionManager();
      addTearDown(connectionManager.disconnect);

      await connectionManager.connect(
        host: '127.0.0.1',
        port: port,
      );

      final clientDir = await Directory.systemTemp.createTemp('ft_client_');
      addTearDown(() => clientDir.delete(recursive: true));
      final outputPath = p.join(clientDir.path, 'received.bin');

      final result = await connectionManager.requestFile(
        filePath: p.join(Directory.systemTemp.path, 'other', 'file.txt'),
        outputPath: outputPath,
      );

      expect(result.isError(), isTrue);
      expect(File(outputPath).existsSync(), isFalse);
    });

    test('Server returns error when file not found', () async {
      final serverDir = await Directory.systemTemp.createTemp('ft_server_');
      addTearDown(() => serverDir.delete(recursive: true));

      final mockLockService = MockFileTransferLockService();
      final fileTransferHandler = FileTransferMessageHandler(
        allowedBasePath: serverDir.path,
        lockService: mockLockService,
      );
      final server = TcpSocketServer(fileTransferHandler: fileTransferHandler);
      final port = getTestPort();
      await server.start(port: port);
      addTearDown(server.stop);
      addTearDown(() => Future<void>.delayed(const Duration(milliseconds: 200)));

      final connectionManager = ConnectionManager();
      addTearDown(connectionManager.disconnect);

      await connectionManager.connect(
        host: '127.0.0.1',
        port: port,
      );

      final clientDir = await Directory.systemTemp.createTemp('ft_client_');
      addTearDown(() => clientDir.delete(recursive: true));
      final outputPath = p.join(clientDir.path, 'received.bin');

      final result = await connectionManager.requestFile(
        filePath: p.normalize(p.join(serverDir.path, 'nonexistent.bin')),
        outputPath: outputPath,
      );

      expect(result.isError(), isTrue);
      expect(File(outputPath).existsSync(), isFalse);
    });

    test('Client listAvailableFiles returns files under server base path', () async {
      final serverDir = await Directory.systemTemp.createTemp('ft_server_');
      addTearDown(() => serverDir.delete(recursive: true));

      final a = File(p.join(serverDir.path, 'a.txt'));
      await a.writeAsString('a');
      final sub = Directory(p.join(serverDir.path, 'sub'));
      await sub.create(recursive: true);
      final b = File(p.join(sub.path, 'b.bin'));
      await b.writeAsString('bb');

      final mockLockService = MockFileTransferLockService();
      final fileTransferHandler = FileTransferMessageHandler(
        allowedBasePath: serverDir.path,
        lockService: mockLockService,
      );
      final server = TcpSocketServer(fileTransferHandler: fileTransferHandler);
      final port = getTestPort();
      await server.start(port: port);
      addTearDown(server.stop);
      addTearDown(() => Future<void>.delayed(const Duration(milliseconds: 200)));

      final connectionManager = ConnectionManager();
      addTearDown(connectionManager.disconnect);

      await connectionManager.connect(
        host: '127.0.0.1',
        port: port,
      );

      final listResult = await connectionManager.listAvailableFiles();
      expect(listResult.isSuccess(), isTrue);

      final files = listResult.getOrNull()!;
      expect(files.length, 2);
      final paths = files.map((e) => e.path).toList()..sort();
      expect(paths, contains('a.txt'));
      expect(paths, contains(p.join('sub', 'b.bin')));
      final aEntry = files.firstWhere((e) => e.path == 'a.txt');
      expect(aEntry.size, 1);
      final bEntry = files.firstWhere((e) => e.path == p.join('sub', 'b.bin'));
      expect(bEntry.size, 2);
    });
  });
}
