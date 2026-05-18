import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirebirdServerVersionHint', () {
    test('parse accepts v-prefixed and dotted version labels', () {
      expect(
        FirebirdServerVersionHint.parse('v25'),
        FirebirdServerVersionHint.v25,
      );
      expect(
        FirebirdServerVersionHint.parse('2.5'),
        FirebirdServerVersionHint.v25,
      );
      expect(
        FirebirdServerVersionHint.parse('  V30  '),
        FirebirdServerVersionHint.v30,
      );
      expect(
        FirebirdServerVersionHint.parse('3.0'),
        FirebirdServerVersionHint.v30,
      );
      expect(
        FirebirdServerVersionHint.parse('v40'),
        FirebirdServerVersionHint.v40,
      );
      expect(
        FirebirdServerVersionHint.parse('4.0'),
        FirebirdServerVersionHint.v40,
      );
    });

    test('parse maps auto and unknown to auto', () {
      expect(
        FirebirdServerVersionHint.parse('auto'),
        FirebirdServerVersionHint.auto,
      );
      expect(
        FirebirdServerVersionHint.parse(''),
        FirebirdServerVersionHint.auto,
      );
      expect(
        FirebirdServerVersionHint.parse('unknown'),
        FirebirdServerVersionHint.auto,
      );
    });

    test('wireValue uses enum name for persistence', () {
      expect(FirebirdServerVersionHint.auto.wireValue, 'auto');
      expect(FirebirdServerVersionHint.v25.wireValue, 'v25');
      expect(FirebirdServerVersionHint.v30.wireValue, 'v30');
      expect(FirebirdServerVersionHint.v40.wireValue, 'v40');
    });
  });

  group('FirebirdServiceManagerMode', () {
    test('parse accepts canonical names case-insensitively', () {
      expect(
        FirebirdServiceManagerMode.parse('auto'),
        FirebirdServiceManagerMode.auto,
      );
      expect(
        FirebirdServiceManagerMode.parse('  ALWAYS '),
        FirebirdServiceManagerMode.always,
      );
      expect(
        FirebirdServiceManagerMode.parse('Never'),
        FirebirdServiceManagerMode.never,
      );
    });

    test('parse maps unknown to auto', () {
      expect(
        FirebirdServiceManagerMode.parse(''),
        FirebirdServiceManagerMode.auto,
      );
      expect(
        FirebirdServiceManagerMode.parse('sometimes'),
        FirebirdServiceManagerMode.auto,
      );
    });

    test('wireValue uses enum name for persistence', () {
      expect(FirebirdServiceManagerMode.auto.wireValue, 'auto');
      expect(FirebirdServiceManagerMode.always.wireValue, 'always');
      expect(FirebirdServiceManagerMode.never.wireValue, 'never');
    });
  });
}
