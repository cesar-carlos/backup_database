abstract class IMetricsCollector {
  void incrementCounter(String name, {int value = 1});

  void recordHistogram(String name, num value);

  Map<String, num> getSnapshot();

  void reset();
}
