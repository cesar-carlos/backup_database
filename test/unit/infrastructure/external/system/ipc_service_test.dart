import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(IpcService.resetPortCacheForTests);
  tearDown(IpcService.resetPortCacheForTests);

  group('IpcService.checkServerRunning', () {
    test(
      'should return true when server responds with valid V1 PONG',
      () async {
        final server = await _bindEphemeralIpcMockServer();

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
      final server = await _bindEphemeralIpcMockServer();

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

    test('should return true when V1 PONG has service role', () async {
      final server = await _bindEphemeralIpcMockServer();

      server.listen((Socket socket) {
        socket.listen((List<int> data) async {
          final message = utf8.decode(data).trim();
          if (message == SingleInstanceConfig.ipcPingMessage) {
            socket.add(
              utf8.encode(
                '${SingleInstanceConfig.ipcPongLinePrefix}'
                'v=${SingleInstanceConfig.ipcProtocolVersion}|'
                'role=${SingleInstanceConfig.ipcInstanceRoleService}|pid=1',
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
    });

    test(
      'should return false when server responds without valid V1 line',
      () async {
        final server = await _bindEphemeralIpcMockServer();

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
        final stack = await _bindSixPortProbeStackLastRespondsV1Pong();
        final decoys = stack.decoys;
        final server = stack.target;

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
          for (final d in decoys) {
            await d.close();
          }
        }
      },
    );
  });

  group('IpcService.getExistingInstanceInfo', () {
    test('should parse V1 PONG role and schedule capability', () async {
      final server = await _bindEphemeralIpcMockServer();

      server.listen((Socket socket) {
        socket.listen((List<int> data) async {
          final message = utf8.decode(data).trim();
          if (message == SingleInstanceConfig.ipcPingMessage) {
            socket.add(
              utf8.encode(
                '${SingleInstanceConfig.ipcPongLinePrefix}'
                'v=${SingleInstanceConfig.ipcProtocolVersion}|'
                'role=${SingleInstanceConfig.ipcInstanceRoleService}|'
                'canRunSchedule=true|pid=1',
              ),
            );
            await socket.flush();
          }
        });
      });

      try {
        final info = await IpcService.getExistingInstanceInfo();

        expect(info, isNotNull);
        expect(info!.role, SingleInstanceConfig.ipcInstanceRoleService);
        expect(info.canRunSchedule, isTrue);
      } finally {
        await server.close();
      }
    });

    test(
      'should default schedule capability to false for legacy V1 PONG',
      () async {
        final server = await _bindEphemeralIpcMockServer();

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
          final info = await IpcService.getExistingInstanceInfo();

          expect(info, isNotNull);
          expect(info!.role, SingleInstanceConfig.ipcInstanceRoleUi);
          expect(info.canRunSchedule, isFalse);
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
        final server = await _bindEphemeralIpcMockServer();

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
      final server = await _bindEphemeralIpcMockServer();
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
      final server = await _bindEphemeralIpcMockServer();

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

    test('should parse V1 USER_INFO with service role', () async {
      final server = await _bindEphemeralIpcMockServer();

      server.listen((Socket socket) {
        socket.listen((List<int> data) async {
          final message = utf8.decode(data).trim();
          if (message == SingleInstanceConfig.ipcGetUserInfoMessage) {
            final u64 = base64Url.encode(utf8.encode('test_user'));
            socket.add(
              utf8.encode(
                '${SingleInstanceConfig.ipcUserInfoLinePrefix}'
                'v=${SingleInstanceConfig.ipcProtocolVersion}|'
                'role=${SingleInstanceConfig.ipcInstanceRoleService}|'
                'pid=1|u64=$u64',
              ),
            );
            await socket.flush();
          }
        });
      });

      try {
        final result = await IpcService.getExistingInstanceUser();
        expect(result, equals('test_user'));
      } finally {
        await server.close();
      }
    });

    test(
      'should return null when V1 USER_INFO has wrong protocol version',
      () async {
        final server = await _bindEphemeralIpcMockServer();

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
      final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final listenEphemeralPort = reserved.port;
      await reserved.close();
      IpcService.ipcPortsOverrideForTests = [listenEphemeralPort];

      final ipc = IpcService();
      var showCount = 0;
      final started = await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleUi,
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

    test('should delegate RUN_SCHEDULE and return exit code', () async {
      final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final listenEphemeralPort = reserved.port;
      await reserved.close();
      IpcService.ipcPortsOverrideForTests = [listenEphemeralPort];

      final ipc = IpcService();
      final started = await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleService,
        onRunSchedule: (scheduleId) async {
          expect(scheduleId, '00000000-0000-4000-8000-000000000001');
          return 0;
        },
      );
      expect(started, isTrue);

      try {
        final result = await IpcService.delegateScheduledExecution(
          '00000000-0000-4000-8000-000000000001',
        );

        expect(result, isNotNull);
        expect(result!.exitCode, 0);
        expect(result.message, SingleInstanceConfig.ipcRunScheduleMessageOk);
      } finally {
        await ipc.stop();
      }
    });

    test('should return capability in PONG from real server', () async {
      final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final listenEphemeralPort = reserved.port;
      await reserved.close();
      IpcService.ipcPortsOverrideForTests = [listenEphemeralPort];

      final ipc = IpcService();
      final started = await ipc.startServer(
        role: SingleInstanceConfig.ipcInstanceRoleService,
        onRunSchedule: (_) async => 0,
      );
      expect(started, isTrue);

      try {
        final info = await IpcService.getExistingInstanceInfo();

        expect(info, isNotNull);
        expect(info!.role, SingleInstanceConfig.ipcInstanceRoleService);
        expect(info.canRunSchedule, isTrue);
      } finally {
        await ipc.stop();
      }
    });

    test(
      'should return owner cannot run schedule when server lacks handler',
      () async {
        final reserved = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final listenEphemeralPort = reserved.port;
        await reserved.close();
        IpcService.ipcPortsOverrideForTests = [listenEphemeralPort];

        final ipc = IpcService();
        final started = await ipc.startServer(
          role: SingleInstanceConfig.ipcInstanceRoleUi,
        );
        expect(started, isTrue);

        try {
          final result = await IpcService.delegateScheduledExecution(
            '00000000-0000-4000-8000-000000000001',
          );

          expect(result, isNotNull);
          expect(result!.exitCode, 1);
          expect(
            result.message,
            SingleInstanceConfig.ipcRunScheduleMessageOwnerCannotRunSchedule,
          );
        } finally {
          await ipc.stop();
        }
      },
    );

    test(
      'should return timeout result when RUN_SCHEDULE owner does not reply',
      () async {
        dotenv.loadFromString(
          envString: 'SCHEDULED_DELEGATION_TIMEOUT_SECONDS=1',
        );
        final server = await _bindEphemeralIpcMockServer();

        server.listen((Socket socket) {
          socket.listen((List<int> _) {
            // Intentionally keep the socket open without responding.
          });
        });

        try {
          final result = await IpcService.delegateScheduledExecution(
            '00000000-0000-4000-8000-000000000001',
          );

          expect(result, isNotNull);
          expect(result!.exitCode, 1);
          expect(
            result.message,
            SingleInstanceConfig.ipcRunScheduleMessageDelegationTimeout,
          );
        } finally {
          dotenv.loadFromString(envString: 'OTHER_KEY=value');
          await server.close();
        }
      },
    );
  });
}

Future<ServerSocket> _bindEphemeralIpcMockServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  IpcService.ipcPortsOverrideForTests = [server.port];
  return server;
}

Future<({List<ServerSocket> decoys, ServerSocket target})>
_bindSixPortProbeStackLastRespondsV1Pong() async {
  final decoys = <ServerSocket>[];
  for (var i = 0; i < 5; i++) {
    final s = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    s.listen((Socket client) {
      client.listen((_) {});
    });
    decoys.add(s);
  }
  final target = await ServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  IpcService.ipcPortsOverrideForTests = [
    ...decoys.map((d) => d.port),
    target.port,
  ];
  return (decoys: decoys, target: target);
}
