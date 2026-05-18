import 'package:backup_database/core/constants/socket_rate_limit.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

/// Resultado da checagem de rate limit por mensagem recebida.
sealed class RateLimitDecision {
  const RateLimitDecision();
}

class RateLimitAllowed extends RateLimitDecision {
  const RateLimitAllowed();
}

class RateLimitDenied extends RateLimitDecision {
  const RateLimitDenied({required this.retryAfterSeconds});

  final int retryAfterSeconds;
}

/// Janela deslizante por cliente: req/s global + mutacoes/minuto.
class SocketRateLimiter {
  SocketRateLimiter({
    int maxRequestsPerSecond =
        SocketRateLimit.maxRequestsPerSecondPerClient,
    int maxMutatingPerMinute =
        SocketRateLimit.maxMutatingCommandsPerMinutePerClient,
    DateTime Function()? clock,
  }) : _maxRequestsPerSecond = maxRequestsPerSecond,
       _maxMutatingPerMinute = maxMutatingPerMinute,
       _clock = clock ?? DateTime.now;

  final int _maxRequestsPerSecond;
  final int _maxMutatingPerMinute;
  final DateTime Function() _clock;

  final List<DateTime> _requestTimestamps = <DateTime>[];
  final List<DateTime> _mutatingTimestamps = <DateTime>[];

  static const Set<MessageType> _exemptTypes = <MessageType>{
    MessageType.authRequest,
    MessageType.authResponse,
    MessageType.authChallenge,
    MessageType.heartbeat,
    MessageType.disconnect,
    MessageType.error,
  };

  static const Set<MessageType> _mutatingTypes = <MessageType>{
    MessageType.executeSchedule,
    MessageType.startBackupRequest,
    MessageType.cancelSchedule,
    MessageType.cancelBackupRequest,
    MessageType.cancelQueuedBackupRequest,
    MessageType.createSchedule,
    MessageType.deleteSchedule,
    MessageType.updateSchedule,
    MessageType.pauseSchedule,
    MessageType.resumeSchedule,
    MessageType.createDatabaseConfigRequest,
    MessageType.updateDatabaseConfigRequest,
    MessageType.deleteDatabaseConfigRequest,
    MessageType.cleanupStagingRequest,
  };

  static bool isMutatingMessageType(MessageType type) =>
      _mutatingTypes.contains(type);

  static bool isExemptFromRateLimit(MessageType type) =>
      _exemptTypes.contains(type);

  RateLimitDecision check(MessageType type) {
    if (isExemptFromRateLimit(type)) {
      return const RateLimitAllowed();
    }

    final now = _clock();
    _pruneOlderThan(_requestTimestamps, now.subtract(const Duration(seconds: 1)));

    if (_requestTimestamps.length >= _maxRequestsPerSecond) {
      return const RateLimitDenied(retryAfterSeconds: 1);
    }

    if (isMutatingMessageType(type)) {
      _pruneOlderThan(
        _mutatingTimestamps,
        now.subtract(const Duration(minutes: 1)),
      );
      if (_mutatingTimestamps.length >= _maxMutatingPerMinute) {
        final oldest = _mutatingTimestamps.first;
        final secondsUntilSlot = oldest
            .add(const Duration(minutes: 1))
            .difference(now)
            .inSeconds;
        return RateLimitDenied(
          retryAfterSeconds: (secondsUntilSlot + 1).clamp(1, 60),
        );
      }
      _mutatingTimestamps.add(now);
    }

    _requestTimestamps.add(now);
    return const RateLimitAllowed();
  }

  void _pruneOlderThan(List<DateTime> timestamps, DateTime cutoff) {
    while (timestamps.isNotEmpty && !timestamps.first.isAfter(cutoff)) {
      timestamps.removeAt(0);
    }
  }
}
