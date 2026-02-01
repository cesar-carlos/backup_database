class DatabaseName {
  DatabaseName(String value) : _value = _validate(value);
  final String _value;

  static String _validate(String name) {
    if (name.isEmpty) {
      throw const DatabaseNameException('Database name cannot be empty');
    }
    if (name.length > 128) {
      throw const DatabaseNameException(
        'Database name too long (max 128 characters)',
      );
    }
    final invalidChars = [
      '/',
      r'\',
      '*',
      '?',
      '"',
      '<',
      '>',
      '|',
      '\x00',
      '\n',
      '\r',
      '\t',
    ];
    if (invalidChars.any(name.contains)) {
      throw const DatabaseNameException(
        'Database name contains invalid characters',
      );
    }
    return name;
  }

  String get value => _value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DatabaseName && other._value == _value;
  }

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => _value;
}

class DatabaseNameException implements Exception {
  const DatabaseNameException(this.message);
  final String message;

  @override
  String toString() => 'DatabaseNameException: $message';
}
