import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/errors/dropbox_failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/infrastructure/external/dropbox/dropbox_destination_service.dart';
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
  group('DropboxDestinationService.getDropboxErrorMessage', () {
    test('TimeoutException maps to timeout message', () {
      final msg = DropboxDestinationService.getDropboxErrorMessage(
        TimeoutException('timed out'),
      );
      expect(msg, contains('Tempo limite excedido'));
    });

    test('SocketException maps to connection error', () {
      final msg = DropboxDestinationService.getDropboxErrorMessage(
        const SocketException('refused'),
      );
      expect(msg, contains('Erro de conexão'));
    });

    test('DioException 401 maps to session expired', () {
      final msg = DropboxDestinationService.getDropboxErrorMessage(
        _dioException(401),
      );
      expect(msg, contains('expirada'));
    });

    test('DioException 507 maps to storage limit', () {
      final msg = DropboxDestinationService.getDropboxErrorMessage(
        _dioException(507),
      );
      expect(msg, contains('armazenamento'));
    });

    test('DioException 409 maps to conflict', () {
      final msg = DropboxDestinationService.getDropboxErrorMessage(
        _dioException(409),
      );
      expect(msg, contains('já existe'));
    });

    test('DropboxFailure with integrity code maps to integrity message', () {
      final msg = DropboxDestinationService.getDropboxErrorMessage(
        const DropboxFailure(
          message: 'content_hash mismatch',
          code: FailureCodes.integrityValidationFailed,
        ),
      );
      expect(msg, contains('integridade'));
    });

    test('error string with embedded 11401 does NOT match 401', () {
      final msg = DropboxDestinationService.getDropboxErrorMessage(
        Exception('internal id 11401 random 5070'),
      );
      expect(msg, contains('Erro no upload para o Dropbox'));
      expect(msg, isNot(contains('expirada')));
    });

    test('error string with insufficient_storage matches 507', () {
      final msg = DropboxDestinationService.getDropboxErrorMessage(
        Exception('insufficient_storage error'),
      );
      expect(msg, contains('armazenamento'));
    });

    test('unknown error falls back to generic', () {
      final msg = DropboxDestinationService.getDropboxErrorMessage(
        Exception('random'),
      );
      expect(msg, contains('Erro no upload para o Dropbox'));
    });
  });
}
