import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive_destination_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;

void main() {
  group('GoogleDriveDestinationService.getGoogleDriveErrorMessage', () {
    test('TimeoutException maps to timeout message', () {
      final msg = GoogleDriveDestinationService.getGoogleDriveErrorMessage(
        TimeoutException('op timed out'),
      );
      expect(msg, contains('Tempo limite excedido'));
    });

    test('SocketException maps to connection error', () {
      final msg = GoogleDriveDestinationService.getGoogleDriveErrorMessage(
        const SocketException('refused'),
      );
      expect(msg, contains('Erro de conexão'));
    });

    test('DetailedApiRequestError 401 maps to session expired', () {
      final msg = GoogleDriveDestinationService.getGoogleDriveErrorMessage(
        drive.DetailedApiRequestError(401, 'unauthorized'),
      );
      expect(msg, contains('expirada'));
    });

    test('DetailedApiRequestError 404 maps to folder not found', () {
      final msg = GoogleDriveDestinationService.getGoogleDriveErrorMessage(
        drive.DetailedApiRequestError(404, 'not found'),
      );
      expect(msg, contains('Pasta de destino'));
    });

    test(
      'GoogleDriveFailure with integrity code maps to integrity message',
      () {
        final msg = GoogleDriveDestinationService.getGoogleDriveErrorMessage(
          const GoogleDriveFailure(
            message: 'md5 mismatch',
            code: FailureCodes.integrityValidationFailed,
          ),
        );
        expect(msg, contains('integridade'));
      },
    );

    test('error string with isolated 403 maps to permission error', () {
      final msg = GoogleDriveDestinationService.getGoogleDriveErrorMessage(
        Exception('status: 403 forbidden'),
      );
      expect(msg, contains('permissão'));
    });

    test('error string with embedded 11401 does NOT match 401', () {
      final msg = GoogleDriveDestinationService.getGoogleDriveErrorMessage(
        Exception('internal id 11401 random 4031'),
      );
      expect(msg, contains('Erro no upload para o Google Drive'));
      expect(msg, isNot(contains('expirada')));
    });

    test('unknown error falls back to generic', () {
      final msg = GoogleDriveDestinationService.getGoogleDriveErrorMessage(
        Exception('something unrelated'),
      );
      expect(msg, contains('Erro no upload para o Google Drive'));
    });

    test('null error returns generic message', () {
      final msg = GoogleDriveDestinationService.getGoogleDriveErrorMessage(
        null,
      );
      expect(msg, contains('Erro no upload para o Google Drive'));
    });
  });
}
