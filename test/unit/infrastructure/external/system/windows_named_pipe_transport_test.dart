import 'dart:async';
import 'dart:io';

import 'package:backup_database/infrastructure/external/system/ipc/ipc_channel.dart';
import 'package:backup_database/infrastructure/external/system/ipc/named_pipe_ffi.dart';
import 'package:backup_database/infrastructure/external/system/ipc/windows_named_pipe_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsNamedPipeTransport.stopServer', () {
    test('returns without starting when the platform has no server', () async {
      final transport = WindowsNamedPipeTransport(
        pipeName: _uniquePipeName(),
        expectedImagePath: Platform.resolvedExecutable,
      );

      final started = await transport.startServer(
        onConnection: (channel) async {
          await channel.close();
        },
      );

      expect(started, isFalse);
      await transport.stopServer();
    }, skip: Platform.isWindows);

    test('releases the pipe name after the listening server stops', () async {
      final pipeName = _uniquePipeName();
      final transport = _transport(pipeName);

      final started = await transport.startServer(
        onConnection: (_) async {},
      );
      expect(started, isTrue);

      await transport.stopServer();

      expect(transport.isServerRunning, isFalse);
      expect(_canCreateFirstPipeInstance(pipeName), isTrue);
    }, skip: !Platform.isWindows);

    test(
      'releases the pipe name while a connection isolate is still open',
      () async {
        final pipeName = _uniquePipeName();
        final server = _transport(pipeName);
        final clientTransport = _transport(pipeName);
        final handlerEntered = Completer<void>();
        final releaseHandler = Completer<void>();
        IIpcChannel? client;

        try {
          final started = await server.startServer(
            onConnection: (_) async {
              if (!handlerEntered.isCompleted) {
                handlerEntered.complete();
              }
              await releaseHandler.future;
            },
          );
          expect(started, isTrue);

          client = await clientTransport.connect(
            timeout: const Duration(seconds: 5),
          );
          expect(client, isNotNull);
          await client!.writeLine('PING');
          await handlerEntered.future.timeout(const Duration(seconds: 5));

          await server.stopServer();
          expect(server.isServerRunning, isFalse);
          expect(_canCreateFirstPipeInstance(pipeName), isTrue);
        } finally {
          if (!releaseHandler.isCompleted) {
            releaseHandler.complete();
          }
          await client?.close();
          await server.stopServer();
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'rejects a peer whose full image path is a different directory',
      () async {
        final executable = Platform.resolvedExecutable;
        final basename = executable.split(r'\').last;
        final pipeName = _uniquePipeName();
        final expectedImagePath = 'C:\\not-the-install-dir\\$basename';
        final server = WindowsNamedPipeTransport(
          pipeName: pipeName,
          expectedImagePath: expectedImagePath,
        );
        final clientTransport = WindowsNamedPipeTransport(
          pipeName: pipeName,
          expectedImagePath: expectedImagePath,
        );

        try {
          final started = await server.startServer(
            onConnection: (_) async {},
          );
          expect(started, isTrue);

          final client = await clientTransport.connect(
            timeout: const Duration(seconds: 2),
          );
          expect(client, isNull);
          await server.stopServer();
          expect(_canCreateFirstPipeInstance(pipeName), isTrue);
        } finally {
          await server.stopServer();
        }
      },
      skip: !Platform.isWindows,
    );
  });
}

WindowsNamedPipeTransport _transport(String pipeName) {
  return WindowsNamedPipeTransport(
    pipeName: pipeName,
    expectedImagePath: Platform.resolvedExecutable,
  );
}

var _pipeNameSerial = 0;

String _uniquePipeName() {
  _pipeNameSerial++;
  final token = DateTime.now().microsecondsSinceEpoch;
  return '\\\\.\\pipe\\BackupDatabase_Ipc_Test_${pid}_${token}_$_pipeNameSerial';
}

bool _canCreateFirstPipeInstance(String pipeName) {
  final handle = NamedPipeFfi.createServerPipe(
    pipeName: pipeName,
    firstInstance: true,
    security: null,
  );
  final created = NamedPipeFfi.handleIsValid(handle);
  if (created) {
    NamedPipeFfi.disconnectAndClose(handle);
  }
  return created;
}
