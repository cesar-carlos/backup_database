import 'package:flutter_test/flutter_test.dart';
import 'package:backup_database/domain/value_objects/database_name.dart';

void main() {
  group('DatabaseName', () {
    test('should create valid database name', () {
      // Arrange & Act
      final databaseName = DatabaseName('MyDatabase');

      // Assert
      expect(databaseName.value, equals('MyDatabase'));
    });

    test('should accept database name with numbers and underscores', () {
      // Arrange & Act
      final databaseName = DatabaseName('MyDB_123');

      // Assert
      expect(databaseName.value, equals('MyDB_123'));
    });

    test('should throw exception when name is empty', () {
      // Arrange & Act & Assert
      expect(
        () => DatabaseName(''),
        throwsA(isA<DatabaseNameException>()),
      );
    });

    test('should throw exception when name exceeds 128 characters', () {
      // Arrange
      final longName = 'a' * 129;

      // Act & Assert
      expect(
        () => DatabaseName(longName),
        throwsA(isA<DatabaseNameException>()),
      );
    });

    test('should throw exception when name contains invalid characters', () {
      // Act & Assert
      expect(
        () => DatabaseName('Invalid/Name'),
        throwsA(isA<DatabaseNameException>()),
      );
    });

    test('should be equal when values are the same', () {
      // Arrange
      final name1 = DatabaseName('TestDB');
      final name2 = DatabaseName('TestDB');

      // Assert
      expect(name1, equals(name2));
      expect(name1.hashCode, equals(name2.hashCode));
    });

    test('should not be equal when values are different', () {
      // Arrange
      final name1 = DatabaseName('TestDB1');
      final name2 = DatabaseName('TestDB2');

      // Assert
      expect(name1, isNot(equals(name2)));
    });
  });
}
