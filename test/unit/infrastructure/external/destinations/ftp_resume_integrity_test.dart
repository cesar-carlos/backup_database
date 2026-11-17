// Mocktail verification uses closures to record the mocked invocation.
// ignore_for_file: unnecessary_lambdas
import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_integrity_verifier.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp/ftp_uploader.dart';
import 'package:backup_database/infrastructure/external/destinations/ftp_destination_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:ftpconnect/src/commands/file.dart';
import 'package:ftpconnect/src/ftp_reply.dart';
import 'package:ftpconnect/src/ftp_socket.dart';
import 'package:mocktail/mocktail.dart';

class _Client extends Mock implements FTPConnect {}

class _Verifier extends Mock implements FtpIntegrityVerifier {}

class _Control extends Mock implements FTPSocket {}

void main() {
  late Directory temp;
  late File source;
  late _Client ftp;
  setUpAll(() {
    registerFallbackValue(File('unused'));
    registerFallbackValue(TransferType.binary);
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ftp_integrity_');
    source = await File('${temp.path}/backup.bak').writeAsBytes([1, 2, 3, 4]);
    ftp = _Client();
    when(() => ftp.setTransferType(any())).thenAnswer((_) async {});
  });
  tearDown(() => temp.delete(recursive: true));

  test('missing empty remote file is uploaded instead of skipped', () async {
    await source.writeAsBytes([]);
    when(() => ftp.sizeFile('empty.part')).thenAnswer((_) async => -1);
    when(
      () => ftp.uploadFile(
        any(),
        sRemoteName: 'empty.part',
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async => true);
    final result = await FtpUploader().performUploadWithResume(
      ftp: ftp,
      sourceFile: source,
      fileSize: 0,
      remotePartName: 'empty.part',
      supportsRestStream: true,
      enableResumeFromConfig: true,
    );
    expect(result.uploaded, isTrue);
    expect(result.resumed, isFalse);
    verify(
      () => ftp.uploadFile(
        any(),
        sRemoteName: 'empty.part',
        onProgress: any(named: 'onProgress'),
      ),
    ).called(1);
  });

  test(
    'existing final requires content verification even in size-only mode',
    () async {
      final verifier = _Verifier();
      when(() => ftp.sizeFile('backup.bak')).thenAnswer((_) async => 4);
      when(
        () => verifier.validateFinalIntegrity(
          ftp: ftp,
          remoteFileName: 'backup.bak',
          expectedSize: 4,
          localSha256: 'local',
          enableStrongIntegrityValidation: true,
          enableReadBackValidation: true,
        ),
      ).thenAnswer(
        (_) async => const FtpIntegrityValidationResult(
          isValid: false,
          errorMessage: 'different contents',
        ),
      );
      expect(
        await FtpUploader(integrityVerifier: verifier)
            .isRemoteFileAlreadyComplete(
              ftp: ftp,
              remoteFileName: 'backup.bak',
              expectedSize: 4,
              localSha256: 'local',
              enableStrongIntegrityValidation: false,
              enableReadBackValidation: false,
            ),
        isFalse,
      );
    },
  );

  test('hash-like filename in reply is not a content checksum', () async {
    final hash = 'a' * 64;
    final name = '$hash.bak';
    when(() => ftp.sizeFile(name)).thenAnswer((_) async => 4);
    when(
      () => ftp.sendCustomCommand(any()),
    ).thenAnswer((_) async => FTPReply(213, '213 SHA-256 unavailable $name'));
    final result = await FtpIntegrityVerifier().validateFinalIntegrity(
      ftp: ftp,
      remoteFileName: name,
      expectedSize: 4,
      localSha256: hash,
      enableStrongIntegrityValidation: true,
      enableReadBackValidation: false,
    );
    expect(result.isValid, isFalse);
    expect(result.failureCode, FailureCodes.ftpIntegrityValidationInconclusive);
  });

  test('hash reply with checksum and filename remains supported', () async {
    final hash = 'a' * 64;
    when(() => ftp.sizeFile('backup.bak')).thenAnswer((_) async => 4);
    when(() => ftp.sendCustomCommand(any())).thenAnswer(
      (_) async => FTPReply(213, '213 SHA-256 0-4 $hash backup.bak'),
    );
    final result = await FtpIntegrityVerifier().validateFinalIntegrity(
      ftp: ftp,
      remoteFileName: 'backup.bak',
      expectedSize: 4,
      localSha256: hash,
      enableStrongIntegrityValidation: true,
      enableReadBackValidation: false,
    );
    expect(result.isValid, isTrue);
  });

  test(
    'SIZE connection failure propagates instead of reporting absence',
    () async {
      final control = _Control();
      when(() => control.sendCommand('SIZE backup.part'))
          .thenThrow(TimeoutException('connection lost'));
      await expectLater(
        FTPFile(control).size('backup.part'),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  for (final message in [
    '213 -1',
    '213 4 garbage',
    '213 999999999999999999999999',
  ]) {
    test('invalid SIZE aborts session: $message', () async {
      final control = _Control();
      when(() => control.sendCommand('SIZE backup.part'))
          .thenAnswer((_) async => FTPReply(213, message));
      await expectLater(
        FTPFile(control).size('backup.part'),
        throwsA(isA<FTPConnectException>()),
      );
      verify(() => control.abort()).called(1);
    });
  }

  for (final failedCommand in ['OPTS HASH SHA-256', 'HASH backup.part']) {
    test(
      'connection loss at $failedCommand does not try alternate commands',
      () async {
        when(() => ftp.sizeFile('backup.part')).thenAnswer((_) async => 4);
        when(() => ftp.sendCustomCommand(any()))
            .thenAnswer((_) async => FTPReply(200, '200 OK'));
        when(() => ftp.sendCustomCommand(failedCommand))
            .thenThrow(const SocketException('connection reset'));
        await expectLater(
          FtpIntegrityVerifier().validateFinalIntegrity(
            ftp: ftp,
            remoteFileName: 'backup.part',
            expectedSize: 4,
            localSha256: 'a' * 64,
            enableStrongIntegrityValidation: true,
            enableReadBackValidation: true,
          ),
          throwsA(isA<SocketException>()),
        );
        verify(() => ftp.abort()).called(1);
        verifyNever(() => ftp.sendCustomCommand('XSHA256 backup.part'));
        verifyNever(() => ftp.downloadFile(any(), any()));
      },
    );
  }

  test('interrupted read-back aborts without repeating RETR and removes local copy', () async {
    File? copy;
    when(() => ftp.sizeFile('backup.part')).thenAnswer((_) async => 4);
    when(() => ftp.sendCustomCommand(any()))
        .thenAnswer((_) async => FTPReply(500, '500 unsupported'));
    when(() => ftp.downloadFile('backup.part', any())).thenAnswer((call) async {
      copy = call.positionalArguments[1] as File;
      await copy!.writeAsBytes([1, 2]);
      throw const SocketException('download interrupted');
    });
    final result = await FtpIntegrityVerifier().validateFinalIntegrity(
      ftp: ftp,
      remoteFileName: 'backup.part',
      expectedSize: 4,
      localSha256: 'a' * 64,
      enableStrongIntegrityValidation: true,
      enableReadBackValidation: true,
    );
    expect(result.isValid, isFalse);
    expect(result.failureCode, FailureCodes.ftpIntegrityValidationInconclusive);
    verify(() => ftp.downloadFile('backup.part', any())).called(1);
    verify(() => ftp.abort()).called(1);
    expect(await copy!.exists(), isFalse);
  });

  test('unconfirmed existing final does not authorize replacement', () async {
    final verifier = _Verifier();
    when(() => ftp.sizeFile('backup.bak')).thenAnswer((_) async => 4);
    when(
      () => verifier.validateFinalIntegrity(
        ftp: ftp,
        remoteFileName: 'backup.bak',
        expectedSize: 4,
        localSha256: 'local',
        enableStrongIntegrityValidation: true,
        enableReadBackValidation: true,
      ),
    ).thenAnswer(
      (_) async => const FtpIntegrityValidationResult(
        isValid: false,
        failureCode: FailureCodes.ftpIntegrityValidationInconclusive,
        errorMessage: 'connection interrupted',
      ),
    );
    await expectLater(
      FtpUploader(integrityVerifier: verifier).isRemoteFileAlreadyComplete(
        ftp: ftp,
        remoteFileName: 'backup.bak',
        expectedSize: 4,
        localSha256: 'local',
        enableStrongIntegrityValidation: true,
        enableReadBackValidation: true,
      ),
      throwsA(isA<FTPConnectException>()),
    );
  });

  test(
    'successful response containing quoted filename is not a hash',
    () async {
      final hash = 'a' * 64;
      when(() => ftp.sizeFile('backup.part')).thenAnswer((_) async => 4);
      when(() => ftp.sendCustomCommand(any())).thenAnswer(
        (_) async => FTPReply(213, '213 Unable to hash "$hash.bak"'),
      );
      final result = await FtpIntegrityVerifier().validateFinalIntegrity(
        ftp: ftp,
        remoteFileName: 'backup.part',
        expectedSize: 4,
        localSha256: hash,
        enableStrongIntegrityValidation: true,
        enableReadBackValidation: false,
      );
      expect(result.isValid, isFalse);
    },
  );

  test(
    'resume failure preserves partial and next connection queries new offset',
    () async {
      final clients = [ftp, _Client()];
      var clientIndex = 0;
      final hash = await FtpIntegrityVerifier().computeSha256Streaming(source);
      for (var index = 0; index < clients.length; index++) {
        final client = clients[index];
        var uploaded = false;
        final offset = index + 2;
        when(() => client.connect()).thenAnswer((_) async => true);
        when(() => client.disconnect()).thenAnswer((_) async => true);
        when(() => client.setTransferType(any())).thenAnswer((_) async {});
        when(() => client.sendCustomCommand(any())).thenAnswer(
          (call) async => call.positionalArguments[0] == 'FEAT'
              ? FTPReply(211, '211 REST STREAM')
              : FTPReply(213, '213 $hash'),
        );
        when(() => client.sizeFile(any())).thenAnswer(
          (call) async =>
              (call.positionalArguments[0] as String).endsWith('.part')
              ? (uploaded ? 4 : offset)
              : -1,
        );
        when(
          () => client.uploadFileWithResume(
            any(),
            offset: offset,
            sRemoteName: 'backup.bak.run_dest.part',
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async {
          if (offset == 2) throw const SocketException('resume interrupted');
          uploaded = true;
          return true;
        });
        when(() => client.rename(any(), any())).thenAnswer((_) async => true);
        when(
          () =>
              client.uploadFile(any(), sRemoteName: any(named: 'sRemoteName')),
        ).thenAnswer((_) async => true);
      }
      final service = FtpDestinationService(
        clientFactory: (_) => clients[clientIndex++],
      );
      const config = FtpDestinationConfig(
        host: 'test',
        username: 'u',
        password: 'p',
        remotePath: '/',
      );
      final first = await service.upload(
        sourceFilePath: source.path,
        config: config,
        runId: 'run',
        destinationId: 'dest',
      );
      expect(first.isError(), isTrue);
      verify(() => clients[0].abort()).called(1);
      verifyNever(() => clients[0].deleteFile(any()));
      verifyNever(() => clients[0].rename(any(), any()));
      final second = await service.upload(
        sourceFilePath: source.path,
        config: config,
        runId: 'run',
        destinationId: 'dest',
      );
      expect(second.isSuccess(), isTrue);
      verify(
        () => clients[1].uploadFileWithResume(
          any(),
          offset: 3,
          sRemoteName: 'backup.bak.run_dest.part',
          onProgress: any(named: 'onProgress'),
        ),
      ).called(1);
      verify(() => clients[1].rename('backup.bak.run_dest.part', 'backup.bak'))
          .called(1);
    },
  );

  for (final scenario in ['inconclusive', 'corrupt', 'rename', 'upload']) {
    test('partial preservation after $scenario failure', () async {
      final verifier = _Verifier();
      when(() => ftp.connect()).thenAnswer((_) async => true);
      when(() => ftp.disconnect()).thenAnswer((_) async => true);
      when(() => ftp.sendCustomCommand('FEAT'))
          .thenAnswer((_) async => FTPReply(211, '211 REST STREAM'));
      when(() => ftp.sizeFile(any())).thenAnswer((_) async => -1);
      when(
        () => ftp.uploadFile(
          any(),
          sRemoteName: any(named: 'sRemoteName'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => scenario != 'upload');
      when(() => ftp.deleteFile(any())).thenAnswer((_) async => true);
      when(() => ftp.rename(any(), any())).thenAnswer((_) async => false);
      when(() => verifier.computeSha256Streaming(any()))
          .thenAnswer((_) async => null);
      when(
        () => verifier.validateFinalIntegrity(
          ftp: ftp,
          remoteFileName: any(named: 'remoteFileName'),
          expectedSize: 4,
          localSha256: null,
          enableStrongIntegrityValidation: false,
          enableReadBackValidation: false,
        ),
      ).thenAnswer(
        (_) async => FtpIntegrityValidationResult(
          isValid: scenario == 'rename',
          errorMessage: scenario,
          failureCode: scenario == 'inconclusive'
              ? FailureCodes.ftpIntegrityValidationInconclusive
              : FailureCodes.ftpIntegrityValidationFailed,
        ),
      );
      final result =
          await FtpDestinationService(
            clientFactory: (_) => ftp,
            integrityVerifier: verifier,
          ).upload(
            sourceFilePath: source.path,
            runId: 'run',
            destinationId: 'dest',
            config: const FtpDestinationConfig(
              host: 'test',
              username: 'u',
              password: 'p',
              remotePath: '/',
            ),
          );
      expect(result.isError(), isTrue);
      if (scenario == 'corrupt') {
        verify(() => ftp.deleteFile('backup.bak.run_dest.part')).called(1);
      } else {
        verifyNever(() => ftp.deleteFile(any()));
      }
      if (scenario != 'rename') verifyNever(() => ftp.rename(any(), any()));
    });
  }
}
