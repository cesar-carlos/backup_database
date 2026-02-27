import 'package:backup_database/infrastructure/external/process/sybase_connection_strategy_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SybaseConnectionStrategyCache', () {
    test('hit de cache usa estrategia armazenada', () {
      final cache = SybaseConnectionStrategyCache();

      cache.put('config-1', 'full', SybaseConnectionMethod.dbisql, 0);
      final result = cache.get('config-1', 'full');

      expect(result, isNotNull);
      expect(result!.method, SybaseConnectionMethod.dbisql);
      expect(result.strategyIndex, 0);
    });

    test('falha na estrategia cacheada invalida cache', () {
      final cache = SybaseConnectionStrategyCache();

      cache.put('config-1', 'full', SybaseConnectionMethod.dbbackup, 2);
      expect(cache.get('config-1', 'full'), isNotNull);

      cache.invalidate('config-1', 'full');
      expect(cache.get('config-1', 'full'), isNull);
    });

    test('cache expirado retorna null', () async {
      final cache = SybaseConnectionStrategyCache(
        ttl: const Duration(milliseconds: 10),
      );

      cache.put('config-1', 'log', SybaseConnectionMethod.dbisql, 1);
      expect(cache.get('config-1', 'log'), isNotNull);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(cache.get('config-1', 'log'), isNull);
    });

    test('chaves diferentes sao isoladas', () {
      final cache = SybaseConnectionStrategyCache();

      cache.put('config-1', 'full', SybaseConnectionMethod.dbisql, 0);
      cache.put('config-2', 'full', SybaseConnectionMethod.dbbackup, 1);
      cache.put('config-1', 'log', SybaseConnectionMethod.dbbackup, 2);

      final full1 = cache.get('config-1', 'full');
      final full2 = cache.get('config-2', 'full');
      final log1 = cache.get('config-1', 'log');

      expect(full1?.method, SybaseConnectionMethod.dbisql);
      expect(full2?.method, SybaseConnectionMethod.dbbackup);
      expect(log1?.method, SybaseConnectionMethod.dbbackup);
    });
  });
}
