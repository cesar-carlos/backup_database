class QueryCache<T> {
  QueryCache({
    required Duration ttl,
    Clock? clock,
  }) : _ttl = ttl,
       _clock = clock ?? const Clock._();

  final Duration _ttl;
  final Clock _clock;
  final Map<String, _CacheEntry<T>> _cache = {};

  T? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    final now = _clock.now();
    if (now.isBefore(entry.expiry)) {
      return entry.value;
    }

    _cache.remove(key);
    return null;
  }

  void put(String key, T value) {
    final expiry = _clock.now().add(_ttl);
    _cache[key] = _CacheEntry(value: value, expiry: expiry);
  }

  void invalidate(String key) {
    _cache.remove(key);
  }

  void clear() {
    _cache.clear();
  }

  int get size => _cache.length;
}

class _CacheEntry<T> {
  _CacheEntry({
    required this.value,
    required this.expiry,
  });

  final T value;
  final DateTime expiry;
}

class Clock {
  const Clock._();

  DateTime now() => DateTime.now();
}
