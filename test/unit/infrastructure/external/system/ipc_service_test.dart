import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IpcService.checkServerRunning', () {
    test('should return true when server responds with PONG', () async {
      final server = await _bindToIpcTestPort();

      server.listen((socket) {
        socket.listen((data) async {
          final message = utf8.decode(data).trim();
          if (message == SingleInstanceConfig.pingCommand) {
            socket.add(utf8.encode(SingleInstanceConfig.pongResponse));
            await socket.flush();
          }
        });
      });

      try {
        final isRunning = await IpcService.checkServerRunning();

        expect(isRunning, isTrue);
      } finally {
        await server.close();
      }
    });

    test('should return false when server responds without PONG', () async {
      final server = await _bindToIpcTestPort();

      server.listen((socket) {
        socket.listen((_) async {
          socket.add(utf8.encode('INVALID_RESPONSE'));
          await socket.flush();
        });
      });

      try {
        final isRunning = await IpcService.checkServerRunning();

        expect(isRunning, isFalse);
      } finally {
        await server.close();
      }
    });

    test(
      'should return true when server responds on alternative port',
      () async {
        final port = SingleInstanceConfig.ipcAlternativePorts.last;
        final server = await _bindToSpecificPort(port);

        server.listen((socket) {
          socket.listen((data) async {
            final message = utf8.decode(data).trim();
            if (message == SingleInstanceConfig.pingCommand) {
              socket.add(utf8.encode(SingleInstanceConfig.pongResponse));
              await socket.flush();
            }
          });
        });

        try {
          final isRunning = await IpcService.checkServerRunning();

          expect(isRunning, isTrue);
        } finally {
          await server.close();
        }
      },
    );
  });

  group('IpcService.getExistingInstanceUser', () {
    test(
      'should close client socket after receiving user info response',
      () async {
        final server = await _bindToIpcTestPort();

        final clientClosedCompleter = Completer<bool>();
        const expectedUser = 'test_user';

        server.listen((socket) {
          socket.listen(
            (data) async {
              final message = utf8.decode(data).trim();
              if (message == SingleInstanceConfig.getUserInfoCommand) {
                socket.add(
                  utf8.encode(
                    '${SingleInstanceConfig.userInfoResponsePrefix}$expectedUser',
                  ),
                );
                await socket.flush();
              }
            },
            onDone: () {
              if (!clientClosedCompleter.isCompleted) {
                clientClosedCompleter.complete(true);
              }
            },
            onError: (_) {
              if (!clientClosedCompleter.isCompleted) {
                clientClosedCompleter.complete(false);
              }
            },
          );
        });

        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!clientClosedCompleter.isCompleted) {
            clientClosedCompleter.complete(false);
          }
        });

        try {
          final result = await IpcService.getExistingInstanceUser();

          expect(result, equals(expectedUser));
          final clientClosed = await clientClosedCompleter.future;
          expect(clientClosed, isTrue);
        } finally {
          await server.close();
        }
      },
    );
  });
}

Future<ServerSocket> _bindToIpcTestPort() async {
  final portsToTry = [
    SingleInstanceConfig.ipcBasePort,
    ...SingleInstanceConfig.ipcAlternativePorts,
  ];

  for (final port in portsToTry) {
    try {
      return await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      continue;
    }
  }

  fail(
    'Nao foi possivel iniciar servidor de teste nas portas IPC: '
    '${portsToTry.join(', ')}',
  );
}

Future<ServerSocket> _bindToSpecificPort(int port) async {
  try {
    return await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  } on SocketException catch (e) {
    fail('Nao foi possivel iniciar servidor de teste na porta $port: $e');
  }
}
