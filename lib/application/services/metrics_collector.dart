import 'package:backup_database/domain/services/i_metrics_collector.dart';

class MetricsCollector implements IMetricsCollector {
  final Map<String, int> _counters = {};
  final Map<String, List<num>> _histograms = {};

  @override
  void incrementCounter(String name, {int value = 1}) {
    _counters[name] = (_counters[name] ?? 0) + value;
  }

  @override
  void recordHistogram(String name, num value) {
    _histograms[name] ??= [];
    _histograms[name]!.add(value);
  }

  @override
  Map<String, num> getSnapshot() {
    final snapshot = <String, num>{};
    for (final e in _counters.entries) {
      snapshot[e.key] = e.value;
    }
    for (final e in _histograms.entries) {
      final values = e.value;
      if (values.isNotEmpty) {
        final sum = values.fold<num>(0, (a, b) => a + b);
        snapshot['${e.key}_sum'] = sum;
        snapshot['${e.key}_count'] = values.length;
      }
    }
    return snapshot;
  }

  @override
  void reset() {
    _counters.clear();
    _histograms.clear();
  }
}
