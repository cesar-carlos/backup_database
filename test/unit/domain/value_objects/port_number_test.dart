import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PortNumber', () {
    test('accepts valid ports in range 1-65535', () {
      expect(PortNumber(1).value, 1);
      expect(PortNumber(5432).value, 5432);
      expect(PortNumber(65535).value, 65535);
    });

    test('rejects port below 1', () {
      expect(
        () => PortNumber(0),
        throwsA(isA<PortNumberException>()),
      );
    });

    test('rejects port above 65535', () {
      expect(
        () => PortNumber(65536),
        throwsA(isA<PortNumberException>()),
      );
    });

    test('equality compares by value', () {
      expect(PortNumber(1433), equals(PortNumber(1433)));
      expect(PortNumber(1433), isNot(equals(PortNumber(1434))));
    });
  });
}
