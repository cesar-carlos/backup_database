import 'dart:async';
import 'dart:io';

import 'package:backup_database/infrastructure/external/system/ipc/ipc_channel.dart';
import 'package:backup_database/infrastructure/external/system/ipc/named_pipe_ffi.dart';
import 'package:backup_database/infrastructure/external/system/ipc/pending_pipe_connection.dart';
import 'package:backup_database/infrastructure/external/system/ipc/windows_named_pipe_transport.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shutdown releases a connected client that never sent a request',
    () async {
      final pipe =
          r'\\.\pipe\BackupDatabaseIdleConnection_'
          '${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final transport = WindowsNamedPipeTransport(pipeName: pipe);
      final client = WindowsNamedPipeTransport(pipeName: pipe);
      addTearDown(transport.stopServer);
      expect(await transport.startServer(onConnection: (_) async {}), isTrue);
      final channel = await client.connect(timeout: const Duration(seconds: 2));
      expect(channel, isNotNull);
      addTearDown(channel!.close);
      await transport.stopServer().timeout(const Duration(seconds: 4));
      expect(transport.isServerRunning, isFalse);
      expect(await transport.startServer(onConnection: (_) async {}), isTrue);
    },
    skip: !Platform.isWindows,
  );
  test(
    'concurrent starts and stop during startup serialize, then allow restart',
    () async {
      final pipe =
          r'\\.\pipe\BackupDatabaseLifecycle_'
          '${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final transport = WindowsNamedPipeTransport(pipeName: pipe);
      addTearDown(transport.stopServer);
      Future<void> handler(IIpcChannel channel) async => channel.close();
      final first = transport.startServer(onConnection: handler);
      final second = transport.startServer(onConnection: handler);
      final stopped = transport.stopServer();
      expect(await first, isTrue);
      expect(await second, isTrue);
      await stopped;
      expect(transport.isServerRunning, isFalse);
      expect(await transport.startServer(onConnection: handler), isTrue);
      expect(transport.isServerRunning, isTrue);
    },
    skip: !Platform.isWindows,
  );

  test(
    'native UI and executor communicate across repeated connections',
    () async {
      final pipe =
          r'\\.\pipe\BackupDatabaseIpcRegression_'
          '${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final server = IpcService(
        transport: WindowsNamedPipeTransport(pipeName: pipe),
      );
      final client = IpcService(
        transport: WindowsNamedPipeTransport(pipeName: pipe),
      );
      addTearDown(server.stop);
      expect(await server.startServer(role: 'service'), isTrue);
      // Also connect from a transport with an active ReceivePort/isolate.
      expect(await server.checkServerRunning(), isTrue);
      for (var i = 0; i < 40; i++) {
        expect(await client.checkServerRunning(), isTrue);
      }
      await server.stop();
      expect(await server.startServer(role: 'service'), isTrue);
      expect(await client.checkServerRunning(), isTrue);
    },
    skip: !Platform.isWindows,
  );

  test('connection completed after timeout is closed exactly once', () async {
    final pending = Completer<int?>();
    final closed = <int>[];
    await expectLater(
      awaitPipeConnection(
        connection: pending.future,
        timeout: Duration.zero,
        close: closed.add,
      ),
      throwsA(isA<TimeoutException>()),
    );
    pending.complete(42);
    await Future<void>.delayed(Duration.zero);
    expect(closed, [42]);
  });

  test(
    'timely handle is transferred, not closed by the timeout helper',
    () async {
      final closed = <int>[];
      expect(
        await awaitPipeConnection(
          connection: Future.value(42),
          timeout: const Duration(seconds: 1),
          close: closed.add,
        ),
        42,
      );
      expect(closed, isEmpty);
    },
  );

  test(
    'late native error does not become an unhandled async failure',
    () async {
      final pending = Completer<int?>();
      await expectLater(
        awaitPipeConnection(
          connection: pending.future,
          timeout: Duration.zero,
          close: (_) => fail('no handle'),
        ),
        throwsA(isA<TimeoutException>()),
      );
      pending.completeError(StateError('native failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'failed native write is reported rather than waiting for a response',
    () async {
      final channel = WindowsPipeClientChannel(
        handle: 42,
        writeNative: (_, _) async => false,
      );
      await expectLater(channel.writeLine('request'), throwsStateError);
    },
  );

  test('successful native write preserves the frame', () async {
    String? sent;
    final channel = WindowsPipeClientChannel(
      handle: 42,
      writeNative: (_, line) async {
        sent = line;
        return true;
      },
    );
    await channel.writeLine('request');
    expect(sent, 'request');
  });

  test('missing native pipe includes Windows error in diagnostics', () {
    expect(
      () => NamedPipeFfi.connectClient(
        pipeName:
            r'\\.\pipe\BackupDatabaseMissingPipe_'
            '$pid',
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.osError?.errorCode,
          'win32 error',
          2,
        ),
      ),
    );
  }, skip: !Platform.isWindows);
}
