class PortNumber {
  PortNumber(int value) : _value = _validate(value);
  final int _value;

  static int _validate(int port) {
    if (port < 1) {
      throw const PortNumberException('Port must be greater than 0');
    }
    if (port > 65535) {
      throw const PortNumberException('Port must be less than 65536');
    }
    return port;
  }

  int get value => _value;

  bool get isDefault => _value == 1433 || _value == 3306 || _value == 5432;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PortNumber && other._value == _value;
  }

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => _value.toString();
}

class PortNumberException implements Exception {
  const PortNumberException(this.message);
  final String message;

  @override
  String toString() => 'PortNumberException: $message';
}
