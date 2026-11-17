import 'package:backup_database/infrastructure/external/system/ipc/pipe_connection_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recycled handle is independent of completion from an older connection',
    () {
      final registry = PipeConnectionRegistry<int>();
      final first = registry.reserve(42);
      expect(registry.finish(first), 42);
      final second = registry.reserve(42);
      expect(second, isNot(first));
      expect(registry.finish(first), isNull);
      expect(registry[second], 42);
      expect(registry.length, 1);
    },
  );

  test(
    'completed connections do not accumulate over a long service lifetime',
    () {
      final registry = PipeConnectionRegistry<int>();
      for (var i = 0; i < 10000; i++) {
        final id = registry.reserve(i % 8);
        registry.finish(id);
      }
      expect(registry.length, 0);
      expect(registry.snapshot, isEmpty);
    },
  );

  test(
    'early completion before worker spawn returns cannot resurrect a slot',
    () {
      final registry = PipeConnectionRegistry<Object>();
      final connection = Object();
      final id = registry.reserve(connection);
      expect(registry[id], same(connection));
      expect(registry.finish(id), same(connection));
      expect(registry[id], isNull);
      expect(registry.finish(id), isNull);
    },
  );
}
