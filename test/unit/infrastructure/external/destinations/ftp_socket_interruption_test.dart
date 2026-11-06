import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';

void main() {
  for (final mode in ['stall', 'truncated', 'cancel', 'slow']) {
    test('read-back $mode has bounded completion and releases sockets', () async {
      final controlServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final dataServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final peers = <Socket>[];
      final commands = <String>[];
      final dataReady = Completer<Socket>();
      final retr = Completer<void>();
      final temp = await Directory.systemTemp.createTemp('ftp_readback_');
      final output = File('${temp.path}/copy');
      dataServer.listen((socket) {
        peers.add(socket);
        // Abort deliberately resets the peer connection on Linux. Observe both
        // directions of the fake server socket so that reset is not unhandled.
        socket.listen(
          (_) {},
          onError: (Object error) {
            if (error is! SocketException) {
              Error.throwWithStackTrace(error, StackTrace.current);
            }
          },
        );
        unawaited(
          socket.done.then<void>(
            (_) {},
            onError: (Object error) {
              if (error is! SocketException) {
                Error.throwWithStackTrace(error, StackTrace.current);
              }
            },
          ),
        );
        dataReady.complete(socket);
      });
      controlServer.listen((peer) {
        peers.add(peer);
        unawaited(
          peer.done.then<void>(
            (_) {},
            onError: (Object error) {
              if (error is! SocketException) {
                Error.throwWithStackTrace(error, StackTrace.current);
              }
            },
          ),
        );
        peer.write('220 Ready\r\n');
        peer
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (cmd) async {
                commands.add(cmd);
                if (cmd.startsWith('USER')) peer.write('230 OK\r\n');
                if (cmd.startsWith('SIZE')) peer.write('213 4\r\n');
                if (cmd == 'PASV') {
                  peer.write(
                    '227 (127,0,0,1,${dataServer.port ~/ 256},${dataServer.port % 256})\r\n',
                  );
                }
                if (cmd.startsWith('RETR')) {
                  peer.write('150 Opening\r\n');
                  final data = await dataReady.future;
                  retr.complete();
                  if (mode == 'truncated') {
                    data.add([1, 2]);
                    await data.close();
                    peer.write('226 Complete\r\n');
                  } else if (mode == 'slow') {
                    for (var i = 0; i < 4; i++) {
                      data.add([i]);
                      await data.flush();
                      await Future<void>.delayed(
                        const Duration(milliseconds: 400),
                      );
                    }
                    await data.close();
                    peer.write('226 Complete\r\n');
                  }
                }
                if (cmd == 'QUIT') peer.write('221 Bye\r\n');
              },
              onError: (Object error) {
                if (error is! SocketException) {
                  Error.throwWithStackTrace(error, StackTrace.current);
                }
              },
            );
      });
      addTearDown(() async {
        for (final peer in peers) {
          peer.destroy();
        }
        await controlServer.close();
        await dataServer.close();
        await temp.delete(recursive: true);
      });
      final ftp = FTPConnect('127.0.0.1', port: controlServer.port, timeout: 1);
      await ftp.connect();
      final download = ftp.downloadFile('backup.part', output);
      final checked = mode == 'slow'
          ? expectLater(download, completion(isTrue))
          : expectLater(download, throwsA(isA<Exception>()));
      await retr.future;
      if (mode == 'cancel') ftp.abort();
      await checked.timeout(const Duration(seconds: 4));
      if (mode == 'slow') {
        expect(await output.readAsBytes(), [0, 1, 2, 3]);
      } else {
        await expectLater(
          ftp.sendCustomCommand('NOOP'),
          throwsA(isA<FTPConnectException>()),
        );
        expect(commands, isNot(contains('NOOP')));
      }
      await ftp.disconnect();
      // Closed local handles allow immediate deletion, including on Windows.
      if (await output.exists()) await output.delete();
    });
  }

  test(
    'control timeout invalidates session and abort interrupts waiting reader',
    () async {
      for (final cancel in [false, true]) {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        Socket? peer;
        final pending = Completer<void>();
        server.listen((socket) {
          peer = socket;
          unawaited(
            socket.done.then<void>(
              (_) {},
              onError: (Object error) {
                if (error is! SocketException) {
                  Error.throwWithStackTrace(error, StackTrace.current);
                }
              },
            ),
          );
          socket.write('220 Ready\r\n');
          socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
                (cmd) {
                  if (cmd.startsWith('USER')) socket.write('230 OK\r\n');
                  if (cmd == 'NOOP') pending.complete();
                },
                onError: (Object error) {
                  if (error is! SocketException) {
                    Error.throwWithStackTrace(error, StackTrace.current);
                  }
                },
              );
        });
        try {
          final ftp = FTPConnect('127.0.0.1', port: server.port, timeout: 1);
          await ftp.connect();
          final response = ftp.sendCustomCommand('NOOP');
          final checked = expectLater(response, throwsA(isA<Exception>()));
          await pending.future;
          if (cancel) ftp.abort();
          await checked.timeout(const Duration(seconds: 2));
          await expectLater(
            ftp.sendCustomCommand('SIZE backup'),
            throwsA(isA<FTPConnectException>()),
          );
          await ftp.disconnect();
        } finally {
          peer?.destroy();
          await server.close();
        }
      }
    },
  );
}
