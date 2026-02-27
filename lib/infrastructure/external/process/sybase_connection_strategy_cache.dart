import 'package:backup_database/core/utils/logger_service.dart';

enum SybaseConnectionMethod {
  dbisql,
  dbbackup,
}

class SybaseCachedStrategy {
  const SybaseCachedStrategy({
    required this.method,
    required this.strategyIndex,
    required this.expiresAt,
  });

  final SybaseConnectionMethod method;
  final int strategyIndex;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class SybaseConnectionStrategyCache {
  SybaseConnectionStrategyCache({
    Duration ttl = const Duration(minutes: 10),
  }) : _ttl = ttl;

  final Duration _ttl;
  final Map<String, SybaseCachedStrategy> _cache = {};

  static String _key(String configId, String backupType) =>
      '$configId|$backupType';

  SybaseCachedStrategy? get(String configId, String backupType) {
    final cached = _cache[_key(configId, backupType)];
    if (cached == null || cached.isExpired) {
      if (cached != null) {
        _cache.remove(_key(configId, backupType));
      }
      return null;
    }
    return cached;
  }

  void put(
    String configId,
    String backupType,
    SybaseConnectionMethod method,
    int strategyIndex,
  ) {
    final key = _key(configId, backupType);
    _cache[key] = SybaseCachedStrategy(
      method: method,
      strategyIndex: strategyIndex,
      expiresAt: DateTime.now().add(_ttl),
    );
    LoggerService.debug(
      'Cache Sybase: $method estratégia ${strategyIndex + 1} para $configId/$backupType',
    );
  }

  void invalidate(String configId, String backupType) {
    final key = _key(configId, backupType);
    if (_cache.remove(key) != null) {
      LoggerService.debug('Cache Sybase invalidado: $configId/$backupType');
    }
  }
}
