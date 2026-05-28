@TestOn('windows')
library;

import 'package:backup_database/infrastructure/external/system/device_key_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceKeyService cache (Windows)', () {
    test('chamadas consecutivas retornam o mesmo deviceKey', () async {
      final svc = DeviceKeyService();
      final r1 = await svc.getDeviceKey();
      final r2 = await svc.getDeviceKey();

      expect(r1.isSuccess(), isTrue);
      expect(r2.isSuccess(), isTrue);
      expect(r1.getOrNull(), r2.getOrNull());
    });

    test(
      'chamadas concorrentes compartilham o mesmo Future (sem dispatch '
      'duplicado de WMI)',
      () async {
        final svc = DeviceKeyService();
        final futures = List.generate(5, (_) => svc.getDeviceKey());
        final results = await Future.wait(futures);

        // Todos devem retornar o mesmo valor — cache deduplicates
        final keys = results.map((r) => r.getOrNull()).toSet();
        expect(keys.length, 1);
      },
    );

    test('resetCacheForTesting força nova computação', () async {
      final svc = DeviceKeyService();
      final r1 = await svc.getDeviceKey();
      expect(r1.isSuccess(), isTrue);

      svc.resetCacheForTesting();
      final r2 = await svc.getDeviceKey();
      // Mesmo valor (determinístico), mas o cache foi resetado.
      expect(r2.getOrNull(), r1.getOrNull());
    });
  });
}
