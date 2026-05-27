import 'package:backup_database/core/utils/http_error_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HttpErrorHelpers.containsHttpStatus', () {
    test('matches isolated status code', () {
      expect(
        HttpErrorHelpers.containsHttpStatus(
          'request failed with status 401 unauthorized',
          401,
        ),
        isTrue,
      );
    });

    test('matches status surrounded by punctuation', () {
      expect(
        HttpErrorHelpers.containsHttpStatus('http: 550 permission', 550),
        isTrue,
      );
      expect(
        HttpErrorHelpers.containsHttpStatus('(403)', 403),
        isTrue,
      );
    });

    test('does NOT match digits embedded in longer numbers', () {
      expect(
        HttpErrorHelpers.containsHttpStatus('error code 11401 received', 401),
        isFalse,
      );
      expect(
        HttpErrorHelpers.containsHttpStatus('value 5500 buf', 550),
        isFalse,
      );
      expect(
        HttpErrorHelpers.containsHttpStatus('id 4011', 401),
        isFalse,
      );
    });
  });

  group('HttpErrorHelpers.firstHttpStatusIn', () {
    test('returns first matching code from list', () {
      expect(
        HttpErrorHelpers.firstHttpStatusIn(
          'http response: 403 forbidden',
          const [401, 403, 404],
        ),
        equals(403),
      );
    });

    test('returns null when no code matches', () {
      expect(
        HttpErrorHelpers.firstHttpStatusIn(
          'something completely different',
          const [401, 403, 404],
        ),
        isNull,
      );
    });

    test('ignores embedded digit sequences', () {
      expect(
        HttpErrorHelpers.firstHttpStatusIn(
          'error 11401 internal',
          const [401, 403, 404],
        ),
        isNull,
      );
    });
  });
}
