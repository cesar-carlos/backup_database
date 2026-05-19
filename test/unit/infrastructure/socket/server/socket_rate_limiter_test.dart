import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/socket/server/socket_rate_limiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SocketRateLimiter', () {
    test('should allow heartbeats without counting toward limits', () {
      final limiter = SocketRateLimiter(maxRequestsPerSecond: 1);

      for (var i = 0; i < 5; i++) {
        expect(
          limiter.check(MessageType.heartbeat),
          isA<RateLimitAllowed>(),
        );
      }
    });

    test('should deny when requests per second exceeded', () {
      var now = DateTime.utc(2026, 1, 1, 12);
      final limiter = SocketRateLimiter(
        maxRequestsPerSecond: 2,
        clock: () => now,
      );

      expect(limiter.check(MessageType.listSchedules), isA<RateLimitAllowed>());
      expect(limiter.check(MessageType.listSchedules), isA<RateLimitAllowed>());

      final denied = limiter.check(MessageType.listSchedules);
      expect(denied, isA<RateLimitDenied>());
      expect((denied as RateLimitDenied).retryAfterSeconds, 1);

      now = now.add(const Duration(seconds: 1));
      expect(limiter.check(MessageType.listSchedules), isA<RateLimitAllowed>());
    });

    test('should deny mutating commands when per-minute limit exceeded', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final limiter = SocketRateLimiter(
        maxRequestsPerSecond: 100,
        maxMutatingPerMinute: 2,
        clock: () => now,
      );

      expect(
        limiter.check(MessageType.startBackupRequest),
        isA<RateLimitAllowed>(),
      );
      expect(
        limiter.check(MessageType.createSchedule),
        isA<RateLimitAllowed>(),
      );

      final denied = limiter.check(MessageType.deleteSchedule);
      expect(denied, isA<RateLimitDenied>());
      final retry = (denied as RateLimitDenied).retryAfterSeconds;
      expect(retry, greaterThanOrEqualTo(1));
      expect(retry, lessThanOrEqualTo(60));
    });

    test('isMutatingMessageType covers start cancel create delete', () {
      expect(
        SocketRateLimiter.isMutatingMessageType(MessageType.startBackupRequest),
        isTrue,
      );
      expect(
        SocketRateLimiter.isMutatingMessageType(
          MessageType.cancelBackupRequest,
        ),
        isTrue,
      );
      expect(
        SocketRateLimiter.isMutatingMessageType(MessageType.createSchedule),
        isTrue,
      );
      expect(
        SocketRateLimiter.isMutatingMessageType(MessageType.deleteSchedule),
        isTrue,
      );
      expect(
        SocketRateLimiter.isMutatingMessageType(MessageType.listSchedules),
        isFalse,
      );
    });
  });
}
