import 'dart:async';

import 'package:backup_database/core/errors/google_drive_failure.dart';
import 'package:backup_database/infrastructure/external/destinations/google_drive/google_drive_auth_client.dart';
import 'package:backup_database/infrastructure/external/google/google_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _Service extends Mock implements GoogleAuthService {}

void main() {
  late _Service service;
  late GoogleDriveAuthClient auth;
  setUp(() {
    service = _Service();
    auth = GoogleDriveAuthClient(service);
  });

  test(
    'should share renewal across concurrent unauthorized operations',
    () async {
      final refresh = Completer<rd.Result<GoogleAuthResult>>();
      final started = Completer<void>();
      var renewals = 0;
      when(() => service.signInSilently(forceRefresh: true)).thenAnswer((_) {
        renewals++;
        if (!started.isCompleted) started.complete();
        return refresh.future;
      });
      Future<int> execute() {
        var attempts = 0;
        return auth.executeWithTokenRefresh(() async {
          if (attempts++ == 0) {
            throw drive.DetailedApiRequestError(401, 'expired');
          }
          return attempts;
        });
      }

      final first = execute();
      final second = execute();
      await started.future;
      refresh.complete(
        const rd.Success(
          GoogleAuthResult(accessToken: 'new', email: 'test@example.test'),
        ),
      );
      expect(await Future.wait([first, second]), [2, 2]);
      expect(renewals, 1);
    },
  );

  test(
    'should reuse renewed credentials after a delayed unauthorized response',
    () async {
      var renewals = 0;
      when(() => service.signInSilently(forceRefresh: true))
          .thenAnswer((_) async {
            renewals++;
            return const rd.Success(
              GoogleAuthResult(accessToken: 'new', email: 'test@example.test'),
            );
          });
      final delayedResponse = Completer<void>();
      var delayedAttempts = 0;
      final delayed = auth.executeWithTokenRefresh(() async {
        if (delayedAttempts++ == 0) {
          await delayedResponse.future;
          throw drive.DetailedApiRequestError(401, 'old response');
        }
        return 'recovered';
      });
      var attempts = 0;
      await auth.executeWithTokenRefresh(() async {
        if (attempts++ == 0) {
          throw drive.DetailedApiRequestError(401, 'expired');
        }
        return 'ok';
      });
      delayedResponse.complete();
      expect(await delayed, 'recovered');
      expect(renewals, 1);
    },
  );

  test('should allow a new renewal after previous renewal failed', () async {
    var renewals = 0;
    when(() => service.signInSilently(forceRefresh: true))
        .thenAnswer((_) async {
          if (renewals++ == 0) {
            return const rd.Failure(
              GoogleDriveFailure(message: 'temporarily offline'),
            );
          }
          return const rd.Success(
            GoogleAuthResult(accessToken: 'new', email: 'test@example.test'),
          );
        });
    await expectLater(
      auth.executeWithTokenRefresh<Object>(() async {
        throw drive.DetailedApiRequestError(401, 'expired');
      }),
      throwsA(isA<GoogleDriveFailure>()),
    );
    var attempts = 0;
    expect(
      await auth.executeWithTokenRefresh(() async {
        if (attempts++ == 0) {
          throw drive.DetailedApiRequestError(401, 'expired');
        }
        return 'ok';
      }),
      'ok',
    );
    expect(renewals, 2);
  });

  for (final status in [403, 500]) {
    test(
      'should honor HTTP $status even if the message mentions unauthorized',
      () async {
        final failure = drive.DetailedApiRequestError(status, 'unauthorized');
        await expectLater(
          auth.executeWithTokenRefresh<Object>(() async {
            throw failure;
          }),
          throwsA(same(failure)),
        );
        verifyNever(() => service.signInSilently(forceRefresh: true));
      },
    );
  }
}
