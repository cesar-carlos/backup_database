import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(IpcService.resetPortCacheForTests);

  group('IpcService.checkServerRunning', () {
    test(
      'should return true when server responds with valid V1 PONG',
      () async {
        final server = await _bindToIpcTestPort();

        server.listen((Socket socket) {
          socket.listen((List<int> data) async {
            final message = utf8.decode(data).trim();
            if (message == SingleInstanceConfig.ipcPingMessage) {
              socket.add(
                utf8.encode(
                  '${SingleInstanceConfig.ipcPongLinePrefix}'
                  'v=${SingleInstanceConfig.ipcProtocolVersion}|'
                  'role=${SingleInstanceConfig.ipcInstanceRoleUi}|pid=1',
                ),
              );
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

    test('should return false when server responds with plain PONG', () async {
      final server = await _bindToIpcTestPort();

      server.listen((Socket socket) {
        socket.listen((List<int> data) async {
          final message = utf8.decode(data).trim();
          if (message == SingleInstanceConfig.ipcPingMessage) {
            socket.add(utf8.encode(SingleInstanceConfig.pongResponse));
            await socket.flush();
          }
        });
      });

      try {
        final isRunning = await IpcService.checkServerRunning();

        expect(isRunning, isFalse);
      } finally {
        await server.close();
      }
    });

    test('should return false when V1 PONG has wrong role', () async {
      final server = await _bindToIpcTestPort();

      server.listen((Socket socket) {
        socket.listen((List<int> data) async {
          final message = utf8.decode(data).trim();
          if (message == SingleInstanceConfig.ipcPingMessage) {
            socket.add(
              utf8.encode(
                '${SingleInstanceConfig.ipcPongLinePrefix}'
                'v=${SingleInstanceConfig.ipcProtocolVersion}|'
                'role=service|pid=1',
              ),
            );
            await socket.flush();
          }
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
      'should return false when server responds without valid V1 line',
      () async {
        final server = await _bindToIpcTestPort();

        server.listen((Socket socket) {
          socket.listen((List<int> _) async {
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
      },
    );

    test(
      'should return true when server responds on alternative port',
      () async {
        final port = SingleInstanceConfig.ipcAlternativePorts.last;
        final server = await _bindToSpecificPort(port);

        server.listen((Socket socket) {
          socket.listen((List<int> data) async {
            final message = utf8.decode(data).trim();
            if (message == SingleInstanceConfig.ipcPingMessage) {
              socket.add(
                utf8.encode(
                  '${SingleInstanceConfig.ipcPongLinePrefix}'
                  'v=${SingleInstanceConfig.ipcProtocolVersion}|'
                  'role=${SingleInstanceConfig.ipcInstanceRoleUi}|pid=1',
                ),
              );
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
      'should close client socket after receiving V1 user info response',
      () async {
        final server = await _bindToIpcTestPort();

        final clientClosedCompleter = Completer<bool>();
        const expectedUser = 'test_user';

        server.listen((Socket socket) {
          socket.listen(
            (List<int> data) async {
              final message = utf8.decode(data).trim();
              if (message == SingleInstanceConfig.ipcGetUserInfoMessage) {
                final u64 = base64Url.encode(utf8.encode(expectedUser));
                socket.add(
                  utf8.encode(
                    '${SingleInstanceConfig.ipcUserInfoLinePrefix}'
                    'v=${SingleInstanceConfig.ipcProtocolVersion}|'
                    'role=${SingleInstanceConfig.ipcInstanceRoleUi}|'
                    'pid=1|u64=$u64',
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

    test('should parse legacy USER_INFO prefix', () async {
      final server = await _bindToIpcTestPort();
      const expectedUser = 'legacy_user';

      server.listen((Socket socket) {
        socket.listen((List<int> data) async {
          final message = utf8.decode(data).trim();
          if (message == SingleInstanceConfig.ipcGetUserInfoMessage) {
            socket.add(
              utf8.encode(
                '${SingleInstanceConfig.userInfoResponsePrefix}$expectedUser',
              ),
            );
            await socket.flush();
          }
        });
      });

      try {
        final result = await IpcService.getExistingInstanceUser();

        expect(result, equals(expectedUser));
      } finally {
        await server.close();
      }
    });

    test('should return null when USER_INFO line is malformed', () async {
      final server = await _bindToIpcTestPort();

      server.listen((Socket socket) {
        socket.listen((List<int> data) async {
          final message = utf8.decode(data).trim();
          if (message == SingleInstanceConfig.ipcGetUserInfoMessage) {
            socket.add(
              utf8.encode(
                '${SingleInstanceConfig.ipcUserInfoLinePrefix}'
                'v=${SingleInstanceConfig.ipcProtocolVersion}|'
                'role=${SingleInstanceConfig.ipcInstanceRoleUi}|pid=1',
              ),
            );
            await socket.flush();
          }
        });
      });

      try {
        final result = await IpcService.getExistingInstanceUser();

        expect(result, isNull);
      } finally {
        await server.close();
      }
    });

    test('should return null when V1 USER_INFO has wrong role', () async {
      final server = await _bindToIpcTestPort();

      server.listen((Socket socket) {
        socket.listen((List<int> data) async {
          final message = utf8.decode(data).trim();
          if (message == SingleInstanceConfig.ipcGetUserInfoMessage) {
            final u64 = base64Url.encode(utf8.encode('test_user'));
            socket.add(
              utf8.encode(
                '${SingleInstanceConfig.ipcUserInfoLinePrefix}'
                'v=${SingleInstanceConfig.ipcProtocolVersion}|'
                'role=service|pid=1|u64=$u64',
              ),
            );
            await socket.flush();
          }
        });
      });

      try {
        final result = await IpcService.getExistingInstanceUser();
        expect(result, isNull);
      } finally {
        await server.close();
      }
    });

    test(
      'should return null when V1 USER_INFO has wrong protocol version',
      () async {
        final server = await _bindToIpcTestPort();

        server.listen((Socket socket) {
          socket.listen((List<int> data) async {
            final message = utf8.decode(data).trim();
            if (message == SingleInstanceConfig.ipcGetUserInfoMessage) {
              final u64 = base64Url.encode(utf8.encode('test_user'));
              socket.add(
                utf8.encode(
                  '${SingleInstanceConfig.ipcUserInfoLinePrefix}'
                  'v=999|'
                  'role=${SingleInstanceConfig.ipcInstanceRoleUi}|pid=1|u64=$u64',
                ),
              );
              await socket.flush();
            }
          });
        });

        try {
          final result = await IpcService.getExistingInstanceUser();
          expect(result, isNull);
        } finally {
          await server.close();
        }
      },
    );
  });

  group('IpcService server (integration)', () {
    test('should accept V1 SHOW_WINDOW and legacy SHOW_WINDOW', () async {
      final ipc = IpcService();
      var showCount = 0;
      final started = await ipc.startServer(
        onShowWindow: () {
          showCount++;
        },
      );
      expect(started, isTrue);

      try {
        final listenPort = ipc.listenPort;
        Socket? s1;
        Socket? s2;
        s1 = await Socket.connect(
          InternetAddress.loopbackIPv4,
          listenPort,
          timeout: const Duration(seconds: 2),
        );
        s1.add(utf8.encode(SingleInstanceConfig.ipcShowWindowMessage));
        await s1.flush();
        await Future.delayed(const Duration(milliseconds: 50));

        s2 = await Socket.connect(
          InternetAddress.loopbackIPv4,
          listenPort,
          timeout: const Duration(seconds: 2),
        );
        s2.add(utf8.encode(SingleInstanceConfig.showWindowCommand));
        await s2.flush();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(showCount, 2);
        await s1.close();
        await s2.close();
      } finally {
        await ipc.stop();
      }
    });
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
