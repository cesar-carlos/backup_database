import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/di/service_locator.dart' as di;
import 'package:backup_database/core/logging/socket_logger_service.dart';
import 'package:backup_database/domain/services/i_file_transfer_lock_service.dart';
import 'package:backup_database/infrastructure/protocol/file_chunker.dart';
import 'package:backup_database/infrastructure/protocol/file_transfer_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class MockFileTransferLockService implements IFileTransferLockService {
  @override
  Future<bool> tryAcquireLock(String filePath) async => true;

  @override
  Future<void> releaseLock(String filePath) async {}

  @override
  Future<bool> isLocked(String filePath) async => false;

  @override
  Future<void> cleanupExpiredLocks({
    Duration maxAge = const Duration(minutes: 30),
  }) async {}
}

int _nextPort = 29600;

int getTestPort() {
  final port = _nextPort;
  _nextPort++;
  return port;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Directory? socketLogsDir;

  setUpAll(() async {
    socketLogsDir = await Directory.systemTemp.createTemp('socket_logs_');
    if (di.getIt.isRegistered<SocketLoggerService>()) {
      await di.getIt.unregister<SocketLoggerService>();
    }
    final socketLogger = SocketLoggerService(logsDirectory: socketLogsDir!.path)
      ..isEnabled = false;
    await socketLogger.initialize();
    di.getIt.registerSingleton<SocketLoggerService>(socketLogger);
  });

  tearDownAll(() async {
    if (di.getIt.isRegistered<SocketLoggerService>()) {
      await di.getIt.unregister<SocketLoggerService>();
    }
    if (socketLogsDir != null && await socketLogsDir!.exists()) {
      await socketLogsDir!.delete(recursive: true);
    }
  });

  group('File Transfer Integration', () {
    test('Server sends file and client receives correctly', () async {
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
      addTearDown(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );

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
      addTearDown(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );

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
      addTearDown(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );

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

    test(
      'Client listAvailableFiles returns files under server base path',
      () async {
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
        final server = TcpSocketServer(
          fileTransferHandler: fileTransferHandler,
        );
        final port = getTestPort();
        await server.start(port: port);
        addTearDown(server.stop);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

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
        final bEntry = files.firstWhere(
          (e) => e.path == p.join('sub', 'b.bin'),
        );
        expect(bEntry.size, 2);
      },
    );

    test('Client resumes download after disconnect using startChunk', () async {
      final serverDir = await Directory.systemTemp.createTemp('ft_server_');
      addTearDown(() => serverDir.delete(recursive: true));

      final sourceBytes = List<int>.generate(
        512 * 1024,
        (index) => index % 256,
      );
      final serverFile = File(p.join(serverDir.path, 'large.bin'));
      await serverFile.writeAsBytes(sourceBytes, flush: true);

      final fileTransferHandler = FileTransferMessageHandler(
        allowedBasePath: serverDir.path,
        lockService: MockFileTransferLockService(),
        chunker: FileChunker(chunkSize: 64 * 1024),
      );
      final server = TcpSocketServer(fileTransferHandler: fileTransferHandler);
      final port = getTestPort();
      await server.start(port: port);
      addTearDown(server.stop);
      addTearDown(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );

      final startChunks = <int>[];
      final msgSub = server.messageStream.listen((message) {
        if (isFileTransferStartRequest(message)) {
          startChunks.add(getStartChunkFromRequest(message));
        }
      });
      addTearDown(msgSub.cancel);

      final manager = ConnectionManager();
      addTearDown(manager.disconnect);
      await manager.connect(host: '127.0.0.1', port: port);

      final clientDir = await Directory.systemTemp.createTemp('ft_client_');
      addTearDown(() => clientDir.delete(recursive: true));
      final outputPath = p.join(clientDir.path, 'large.bin');

      var disconnectTriggered = false;
      final firstAttempt = manager.requestFile(
        filePath: 'large.bin',
        outputPath: outputPath,
        onProgress: (currentChunk, totalChunks) {
          if (disconnectTriggered || currentChunk != 1 || totalChunks <= 1) {
            return;
          }
          disconnectTriggered = true;
          unawaited(manager.disconnect());
        },
      );

      final firstResult = await firstAttempt;
      expect(firstResult.isError(), isTrue);

      final partFile = File('$outputPath.part');
      expect(await partFile.exists(), isTrue);
      final partialSize = await partFile.length();
      expect(partialSize, greaterThan(0));

      await manager.connect(host: '127.0.0.1', port: port);
      final secondResult = await manager.requestFile(
        filePath: 'large.bin',
        outputPath: outputPath,
      );
      expect(secondResult.isSuccess(), isTrue);

      final outputFile = File(outputPath);
      expect(await outputFile.exists(), isTrue);
      expect(await outputFile.readAsBytes(), sourceBytes);

      expect(startChunks.length, greaterThanOrEqualTo(2));
      expect(startChunks.first, 0);
      expect(startChunks[1], greaterThan(0));

      expect(await File('$outputPath.part').exists(), isFalse);
      expect(await File('$outputPath.part.meta.json').exists(), isFalse);
    });

    test(
      'Client restarts download from zero when part exists without metadata',
      () async {
        final serverDir = await Directory.systemTemp.createTemp('ft_server_');
        addTearDown(() => serverDir.delete(recursive: true));

        final sourceBytes = List<int>.generate(
          256 * 1024,
          (index) => index % 256,
        );
        final serverFile = File(p.join(serverDir.path, 'large.bin'));
        await serverFile.writeAsBytes(sourceBytes, flush: true);

        final fileTransferHandler = FileTransferMessageHandler(
          allowedBasePath: serverDir.path,
          lockService: MockFileTransferLockService(),
          chunker: FileChunker(chunkSize: 64 * 1024),
        );
        final server = TcpSocketServer(
          fileTransferHandler: fileTransferHandler,
        );
        final port = getTestPort();
        await server.start(port: port);
        addTearDown(server.stop);
        addTearDown(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );

        final startChunks = <int>[];
        final msgSub = server.messageStream.listen((message) {
          if (isFileTransferStartRequest(message)) {
            startChunks.add(getStartChunkFromRequest(message));
          }
        });
        addTearDown(msgSub.cancel);

        final manager = ConnectionManager();
        addTearDown(manager.disconnect);
        await manager.connect(host: '127.0.0.1', port: port);

        final clientDir = await Directory.systemTemp.createTemp('ft_client_');
        addTearDown(() => clientDir.delete(recursive: true));
        final outputPath = p.join(clientDir.path, 'large.bin');
        final partPath = '$outputPath.part';

        await File(partPath).writeAsBytes(
          List<int>.generate((64 * 1024) + 321, (index) => (index * 3) % 256),
          flush: true,
        );
        expect(await File('$outputPath.part.meta.json').exists(), isFalse);

        final result = await manager.requestFile(
          filePath: 'large.bin',
          outputPath: outputPath,
        );
        expect(result.isSuccess(), isTrue);
        expect(startChunks, isNotEmpty);
        expect(startChunks.first, 0);

        final outputFile = File(outputPath);
        expect(await outputFile.exists(), isTrue);
        expect(await outputFile.readAsBytes(), sourceBytes);
        expect(await File(partPath).exists(), isFalse);
        expect(await File('$outputPath.part.meta.json').exists(), isFalse);
      },
    );
  });
}
