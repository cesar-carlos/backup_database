import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/errors/failure_diagnostics.dart';
import 'package:backup_database/core/logging/file_logger_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/src/logger.dart' as ftp;

void main() {
  test('console hides credentials in messages, errors and stack traces', () {
    LoggerService.resetForTesting();
    addTearDown(LoggerService.resetForTesting);
    final lines = <String>[];
    runZoned(
      () {
        LoggerService.error(
          'passwordHash=hash-secret requestId=123',
          StateError('client_secret=exception-secret'),
          StackTrace.fromString('password=stack-secret'),
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => lines.add(line),
      ),
    );
    final output = lines.join('\n');
    expect(output, contains('requestId=123'));
    for (final secret in ['hash-secret', 'exception-secret', 'stack-secret']) {
      expect(output.contains(secret), isFalse);
    }
  });
  test('redacts transport credentials while preserving diagnostics', () {
    const input =
        'HTTP 401 password="a secret" refreshToken=refresh-secret '
        'client_secret=client-secret Authorization: Basic abc123 '
        'ftp://user:ftp-secret@host/file BACKUP_DATABASE_LICENSE_PRIVATE_KEY=private-secret';
    final result = redactFailureDetails(input);
    for (final secret in [
      'a secret',
      'refresh-secret',
      'client-secret',
      'abc123',
      'ftp-secret',
      'private-secret',
    ]) {
      expect(result.contains(secret), isFalse);
    }
    expect(result, contains('HTTP 401'));
    expect(result, contains('host/file'));
    expect(
      redactFailureDetails(
        '-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----',
      ),
      isNot(contains('secret')),
    );
  });

  test('FTP command and server echo do not print credentials', () {
    final lines = <String>[];
    runZoned(
      () {
        final logger = ftp.Logger(isEnabled: true);
        logger.log('> PASS ftp-password');
        logger.log('< 530 rejected ftp-password');
        logger.log('> ACCT account-secret');
        logger.log('> ADAT auth-secret');
        logger.log('> REST 1024');
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => lines.add(line),
      ),
    );
    final output = lines.join('\n');
    for (final secret in ['ftp-password', 'account-secret', 'auth-secret']) {
      expect(output.contains(secret), isFalse);
    }
    expect(output, contains('REST 1024'));
    expect(output, contains('530'));
  });

  test('direct file logger calls are also redacted', () async {
    final directory = await Directory.systemTemp.createTemp('redaction-');
    addTearDown(() => directory.delete(recursive: true));
    final logger = FileLoggerService(logsDirectory: directory.path);
    await logger.initialize();
    await logger.log('password=file-secret requestId=123');
    final file = await directory
        .list()
        .where((file) => file.path.endsWith('.log'))
        .first;
    final content = await File(file.path).readAsString();
    expect(content.contains('file-secret'), isFalse);
    expect(content, contains('requestId=123'));
  });
}
