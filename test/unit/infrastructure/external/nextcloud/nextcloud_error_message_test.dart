import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/nextcloud_failure.dart';
import 'package:backup_database/infrastructure/external/nextcloud/nextcloud_destination_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _dioException(int statusCode) {
  return DioException(
    requestOptions: RequestOptions(path: '/'),
    response: Response<dynamic>(
      requestOptions: RequestOptions(path: '/'),
      statusCode: statusCode,
    ),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('NextcloudDestinationService.getNextcloudErrorMessage', () {
    test('TimeoutException maps to timeout message', () {
      final msg = NextcloudDestinationService.getNextcloudErrorMessage(
        TimeoutException('timed out'),
      );
      expect(msg, contains('Tempo limite excedido'));
    });

    test('TlsException maps to TLS error', () {
      final msg = NextcloudDestinationService.getNextcloudErrorMessage(
        const TlsException('bad cert'),
      );
      expect(msg, contains('TLS'));
    });

    test('HandshakeException maps to TLS error', () {
      final msg = NextcloudDestinationService.getNextcloudErrorMessage(
        const HandshakeException('handshake failed'),
      );
      expect(msg, contains('TLS'));
    });

    test('SocketException maps to connection error', () {
      final msg = NextcloudDestinationService.getNextcloudErrorMessage(
        const SocketException('refused'),
      );
      expect(msg, contains('Erro de conexão'));
    });

    test('DioException 401 maps to invalid credentials', () {
      final msg = NextcloudDestinationService.getNextcloudErrorMessage(
        _dioException(401),
      );
      expect(msg, contains('Credenciais'));
    });

    test('DioException 507 maps to storage error', () {
      final msg = NextcloudDestinationService.getNextcloudErrorMessage(
        _dioException(507),
      );
      expect(msg, contains('Armazenamento'));
    });

    test('NextcloudFailure with integrity code maps to integrity message', () {
      final msg = NextcloudDestinationService.getNextcloudErrorMessage(
        const NextcloudFailure(
          message: 'sha-256 mismatch',
          code: FailureCodes.integrityValidationFailed,
        ),
      );
      expect(msg, contains('integridade'));
    });

    test('error string with embedded 11401 does NOT match 401', () {
      final msg = NextcloudDestinationService.getNextcloudErrorMessage(
        Exception('internal id 11401 random 5070'),
      );
      expect(msg, contains('Erro no Nextcloud'));
      expect(msg, isNot(contains('Credenciais')));
    });

    test('unknown error falls back to generic', () {
      final msg = NextcloudDestinationService.getNextcloudErrorMessage(
        Exception('random'),
      );
      expect(msg, contains('Erro no Nextcloud'));
    });
  });
}
