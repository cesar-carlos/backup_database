import 'package:backup_database/domain/value_objects/port_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PortNumber.isDefault', () {
    test('returns true for common default ports', () {
      expect(PortNumber(1433).isDefault, isTrue);
      expect(PortNumber(2638).isDefault, isTrue);
      expect(PortNumber(3050).isDefault, isTrue);
      expect(PortNumber(3306).isDefault, isTrue);
      expect(PortNumber(5432).isDefault, isTrue);
    });

    test('returns false for non-default ports', () {
      expect(PortNumber(5000).isDefault, isFalse);
      expect(PortNumber(1434).isDefault, isFalse);
    });
  });
}
