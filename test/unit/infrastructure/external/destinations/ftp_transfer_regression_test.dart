// Mocktail verification deliberately uses closures.
// ignore_for_file: unnecessary_lambdas, prefer_foreach

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/utils/upload_cancellation.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_integrity_verifier.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_uploader.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp_destination_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';
// Exercise the vendored transport, including its control/data boundary.
import 'package:ftpconnect/src/commands/file.dart';
import 'package:ftpconnect/src/ftp_reply.dart';
import 'package:ftpconnect/src/ftp_socket.dart';
import 'package:mocktail/mocktail.dart';

class _Client extends Mock implements FTPConnect {}

class _Control extends Mock implements FTPSocket {
  _Control() {
    when(() => whenAborted).thenAnswer((_) => Completer<void>().future);
  }
}

class _Data extends Mock implements Socket {}

class _Verifier extends Mock implements FtpIntegrityVerifier {}

void main() {
  late Directory temp;
  late File source;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ftp_regression_');
    source = await File('${temp.path}/backup.bak').writeAsBytes([1, 2, 3, 4]);
  });
  tearDown(() => temp.delete(recursive: true));
  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
    registerFallbackValue(File('unused'));
    registerFallbackValue(TransferType.binary);
  });

  test(
    'control replies survive fragmentation, multiline and coalescing',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      server.listen((peer) {
        peers.add(peer);
        peer.write('220 Ready\r\n');
        peer
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((
              cmd,
            ) async {
              if (cmd.startsWith('USER')) peer.write('230 Logged in\r\n');
              if (cmd == 'FEAT') {
                peer.write('211-Features\r\n REST STR');
                await peer.flush();
                await Future<void>.delayed(const Duration(milliseconds: 40));
                peer.write('EAM\r\n211 End\r\n226 Complete\r\n');
              }
              if (cmd == 'TYPE I') peer.write('504 Refused\r\n');
              if (cmd == 'QUIT') peer.write('221 Bye\r\n');
            });
      });
      addTearDown(() async {
        for (final peer in peers) {
          peer.destroy();
        }
        await server.close();
      });
      final control = FTPSocket(
        '127.0.0.1',
        server.port,
        SecurityType.ftp,
        Logger(isEnabled: true),
        2,
      );
      await control.connect('user', 'pass');
      final feature = await control.sendCommand('FEAT');
      expect(feature.code, 211);
      expect(feature.message, contains('REST STREAM'));
      expect((await control.readResponse()).code, 226);
      await expectLater(
        control.setTransferType(TransferType.binary),
        throwsA(isA<FTPConnectException>()),
      );
      expect(control.transferType, TransferType.auto);
      await control.disconnect();
    },
  );

  test(
    'progress cancellation closes data socket without confirming upload',
    () async {
      final control = _Control();
      final data = _Data();
      when(() => control.timeout).thenReturn(2);
      when(() => control.supportIPV6).thenReturn(false);
      when(() => control.openDataTransferChannel())
          .thenAnswer((_) async => FTPReply(227, '227 (127,0,0,1,8,1)'));
      when(() => control.openDataSocket(any())).thenAnswer((_) async => data);
      when(() => control.sendCommand('STOR backup.part'))
          .thenAnswer((_) async => FTPReply(150, '150 Opening'));
      when(() => data.addStream(any())).thenAnswer((call) async {
        await (call.positionalArguments[0] as Stream<List<int>>).drain<void>();
      });
      await expectLater(
        FTPFile(control).upload(
          source,
          remoteName: 'backup.part',
          onProgress: (_, _, _) => throw StateError('cancelled'),
        ),
        throwsStateError,
      );
      verify(() => control.releaseDataSocket(data)).called(1);
      verifyNever(() => control.readResponse());
    },
  );

  test('failed authentication closes the control connection', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closed = Completer<void>();
    Socket? peer;
    server.listen((socket) {
      peer = socket;
      socket.write('220 Ready\r\n');
      socket.listen(
        (_) => socket.write('530 Denied\r\n'),
        onDone: () => closed.complete(),
      );
    });
    addTearDown(() async {
      peer?.destroy();
      await server.close();
    });
    final control = FTPSocket(
      '127.0.0.1',
      server.port,
      SecurityType.ftp,
      Logger(),
      2,
    );
    await expectLater(
      control.connect('bad', 'bad'),
      throwsA(isA<FTPConnectException>()),
    );
    await closed.future.timeout(const Duration(seconds: 3));
  });

  for (final finalCode in [226, 426, 200]) {
    test(
      'resume accepts 350 and requires transfer completion ($finalCode)',
      () async {
        final control = _Control();
        final data = _Data();
        final sent = <int>[];
        when(() => control.timeout).thenReturn(2);
        when(() => control.supportIPV6).thenReturn(false);
        when(() => control.openDataTransferChannel())
            .thenAnswer((_) async => FTPReply(227, '227 (127,0,0,1,8,1)'));
        when(() => control.openDataSocket(any())).thenAnswer((_) async => data);
        when(() => control.sendCommand('REST 2'))
            .thenAnswer((_) async => FTPReply(350, '350 Restart accepted'));
        when(() => control.sendCommand('STOR backup.part'))
            .thenAnswer((_) async => FTPReply(150, '150 Opening'));
        when(() => control.readResponse())
            .thenAnswer((_) async => FTPReply(finalCode, '$finalCode Result'));
        when(() => data.addStream(any())).thenAnswer((call) async {
          await for (final bytes
              in call.positionalArguments[0] as Stream<List<int>>) {
            sent.addAll(bytes);
          }
        });
        when(() => data.flush()).thenAnswer((_) async {});
        when(() => data.close()).thenAnswer((_) async => data);
        final operation = FTPFile(control)
            .uploadWithResume(source, offset: 2, remoteName: 'backup.part');
        if (finalCode == 226) {
          expect(await operation, isTrue);
        } else {
          await expectLater(operation, throwsA(isA<FTPConnectException>()));
        }
        expect(sent, [3, 4]);
        verifyInOrder([
          () => control.openDataTransferChannel(),
          () => control.sendCommand('REST 2'),
          () => control.sendCommand('STOR backup.part'),
        ]);
        verify(() => control.releaseDataSocket(data)).called(1);
      },
    );
  }

  test(
    'stalled writer fails even if destroying socket does not finish addStream',
    () async {
      final control = _Control();
      final data = _Data();
      when(() => control.timeout).thenReturn(1);
      when(() => control.supportIPV6).thenReturn(false);
      when(() => control.openDataTransferChannel())
          .thenAnswer((_) async => FTPReply(227, '227 (127,0,0,1,8,1)'));
      when(() => control.openDataSocket(any())).thenAnswer((_) async => data);
      when(() => control.sendCommand('STOR backup.part'))
          .thenAnswer((_) async => FTPReply(150, '150 Opening'));
      when(() => data.addStream(any()))
          .thenAnswer((_) => Completer<void>().future);
      await expectLater(
        FTPFile(control)
            .upload(source, remoteName: 'backup.part')
            .timeout(const Duration(seconds: 3)),
        throwsA(isA<TimeoutException>()),
      );
      verify(() => control.abort()).called(greaterThanOrEqualTo(1));
      verify(() => control.releaseDataSocket(data)).called(1);
      verifyNever(() => control.readResponse());
    },
  );

  for (final keepPart in [true, false]) {
    test(
      'socket cancellation is reported as cancelled, keepPart=$keepPart',
      () async {
        final ftp = _Client();
        final cleanup = _Client();
        final verifier = _Verifier();
        var cancelled = false;
        var clients = 0;
        when(() => verifier.computeSha256Streaming(any()))
            .thenAnswer((_) async => null);
        when(() => ftp.connect()).thenAnswer((_) async => true);
        when(() => ftp.sendCustomCommand('FEAT')).thenAnswer((_) async {
          cancelled = true;
          throw const SocketException('interrupted');
        });
        when(() => ftp.setTransferType(any()))
            .thenThrow(const SocketException('closed'));
        when(() => cleanup.connect()).thenAnswer((_) async => true);
        when(() => cleanup.setTransferType(any())).thenAnswer((_) async {});
        when(() => cleanup.changeDirectory('/')).thenAnswer((_) async => true);
        when(() => cleanup.deleteFile(any())).thenAnswer((_) async => true);
        final result =
            await FtpDestinationService(
              clientFactory: (_) => clients++ == 0 ? ftp : cleanup,
              integrityVerifier: verifier,
            ).upload(
              sourceFilePath: source.path,
              isCancelled: () => cancelled,
              config: FtpDestinationConfig(
                host: 'test',
                username: 'u',
                password: 'p',
                remotePath: '/',
                keepPartOnCancel: keepPart,
              ),
            );
        expect(result.exceptionOrNull(), UploadCancellation.cancelledFailure);
        verifyNever(() => ftp.deleteFile(any()));
        verifyNever(() => ftp.disconnect());
        verify(() => ftp.abort()).called(1);
        expect(clients, keepPart ? 1 : 2);
        if (!keepPart) {
          verify(() => cleanup.deleteFile(any(that: endsWith('.part'))))
              .called(1);
          verify(() => cleanup.abort()).called(1);
        }
      },
    );
  }

  test('already cancelled never connects', () async {
    final result =
        await FtpDestinationService(
          clientFactory: (_) => throw StateError('must not connect'),
        ).upload(
          sourceFilePath: source.path,
          isCancelled: () => true,
          config: const FtpDestinationConfig(
            host: 'test',
            username: 'u',
            password: 'p',
            remotePath: '/',
          ),
        );
    expect(result.exceptionOrNull(), UploadCancellation.cancelledFailure);
  });

  test('cancellation watcher aborts without sending QUIT', () async {
    final ftp = _Client();
    final timer = FtpUploader().startCancellationWatcher(
      ftp: ftp,
      isCancelled: () => true,
      context: 'test',
    );
    addTearDown(() => timer?.cancel());
    await Future<void>.delayed(const Duration(milliseconds: 1150));
    verify(() => ftp.abort()).called(1);
    verifyNever(() => ftp.disconnect());
  });

  test('refused binary mode is propagated', () async {
    final ftp = _Client();
    when(() => ftp.setTransferType(TransferType.binary))
        .thenThrow(Exception('504 TYPE refused'));
    await expectLater(
      FtpUploader().ensureBinaryTransferType(ftp),
      throwsException,
    );
  });

  test('directory creation never ignores denied CWD', () async {
    final ftp = _Client();
    when(() => ftp.currentDirectory()).thenAnswer((_) async => '/home');
    when(() => ftp.changeDirectory(any())).thenAnswer((_) async => false);
    when(() => ftp.makeDirectory(any())).thenAnswer((_) async => false);
    await expectLater(
      FtpUploader().createRemoteDirectories(ftp, 'backups'),
      throwsException,
    );
  });

  test(
    'absolute directory starts at root and restores login directory',
    () async {
      final ftp = _Client();
      when(() => ftp.currentDirectory()).thenAnswer((_) async => '/home');
      when(() => ftp.changeDirectory(any())).thenAnswer((_) async => true);
      await FtpUploader().createRemoteDirectories(ftp, '/backups/daily');
      verifyInOrder([
        () => ftp.changeDirectory('/'),
        () => ftp.changeDirectory('backups'),
        () => ftp.changeDirectory('daily'),
        () => ftp.changeDirectory('/home'),
      ]);
    },
  );

  for (final remoteSize in [0, 2, 4]) {
    for (final valid in [false, true]) {
      test(
        'integrity $valid at offset $remoteSize is checked before publish',
        () async {
          final ftp = _Client();
          final verifier = _Verifier();
          when(() => ftp.connect()).thenAnswer((_) async => true);
          when(() => ftp.disconnect()).thenAnswer((_) async => true);
          when(() => ftp.setTransferType(any())).thenAnswer((_) async {});
          when(() => ftp.sendCustomCommand('FEAT'))
              .thenAnswer((_) async => FTPReply(211, '211 REST STREAM'));
          when(() => ftp.sizeFile(any())).thenAnswer(
            (call) async =>
                (call.positionalArguments[0] as String).endsWith('.part')
                ? remoteSize
                : -1,
          );
          when(
            () => ftp.uploadFileWithResume(
              any(),
              offset: any(named: 'offset'),
              sRemoteName: any(named: 'sRemoteName'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => true);
          when(
            () => ftp.uploadFile(
              any(),
              sRemoteName: any(named: 'sRemoteName'),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => true);
          when(() => ftp.deleteFile(any())).thenAnswer((_) async => true);
          when(() => ftp.rename(any(), any())).thenAnswer((_) async => true);
          when(() => verifier.computeSha256Streaming(any()))
              .thenAnswer((_) async => null);
          when(
            () => verifier.validateFinalIntegrity(
              ftp: ftp,
              remoteFileName: any(named: 'remoteFileName'),
              expectedSize: 4,
              localSha256: null,
              enableStrongIntegrityValidation: any(
                named: 'enableStrongIntegrityValidation',
              ),
              enableReadBackValidation: any(named: 'enableReadBackValidation'),
            ),
          ).thenAnswer((call) async {
            expect(call.namedArguments[#remoteFileName], endsWith('.part'));
            expect(
              call.namedArguments[#enableStrongIntegrityValidation],
              remoteSize > 0,
            );
            expect(
              call.namedArguments[#enableReadBackValidation],
              remoteSize > 0,
            );
            verifyNever(() => ftp.rename(any(), any()));
            return FtpIntegrityValidationResult(
              isValid: valid,
              errorMessage: valid ? null : 'corrupt',
            );
          });
          final result =
              await FtpDestinationService(
                clientFactory: (_) => ftp,
                integrityVerifier: verifier,
              ).upload(
                sourceFilePath: source.path,
                config: const FtpDestinationConfig(
                  host: 'test',
                  username: 'u',
                  password: 'p',
                  remotePath: '/',
                ),
              );
          expect(result.isSuccess(), valid);
          verify(() => ftp.disconnect()).called(1);
          if (!valid) {
            verifyNever(() => ftp.rename(any(), any()));
            verifyNever(() => ftp.deleteFile('backup.bak'));
          } else {
            verify(() => ftp.rename(any(), 'backup.bak')).called(1);
          }
        },
      );
    }
  }
}
