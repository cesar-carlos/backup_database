import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SingleInstanceConfig.lockFallbackMode', () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    test('should return fail_open when env is fail_open', () {
      dotenv.loadFromString(
        envString: 'SINGLE_INSTANCE_LOCK_FALLBACK_MODE=fail_open',
      );

      expect(
        SingleInstanceConfig.lockFallbackMode,
        SingleInstanceLockFallbackMode.failOpen,
      );
    });

    test('should return fail_safe when env is fail_safe', () {
      dotenv.loadFromString(
        envString: 'SINGLE_INSTANCE_LOCK_FALLBACK_MODE=fail_safe',
      );

      expect(
        SingleInstanceConfig.lockFallbackMode,
        SingleInstanceLockFallbackMode.failSafe,
      );
    });

    test('should default to fail_safe when key is absent', () {
      dotenv.loadFromString(envString: 'OTHER_KEY=value');

      expect(
        SingleInstanceConfig.lockFallbackMode,
        SingleInstanceLockFallbackMode.failSafe,
      );
    });
  });
}
