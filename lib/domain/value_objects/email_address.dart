class EmailAddress {
  EmailAddress(String value) : _value = _validate(value);
  final String _value;

  static String _validate(String email) {
    if (email.isEmpty) {
      throw const EmailAddressException('Email cannot be empty');
    }

    final trimmed = email.trim();
    if (trimmed != email) {
      throw const EmailAddressException(
        'Email cannot have leading/trailing whitespace',
      );
    }

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(trimmed)) {
      throw const EmailAddressException('Invalid email format');
    }

    final parts = trimmed.split('@');
    if (parts.length != 2) {
      throw const EmailAddressException('Invalid email format');
    }

    final localPart = parts[0];
    final domain = parts[1];

    if (localPart.isEmpty) {
      throw const EmailAddressException('Local part cannot be empty');
    }
    if (localPart.length > 64) {
      throw const EmailAddressException(
        'Local part too long (max 64 characters)',
      );
    }
    if (domain.isEmpty) {
      throw const EmailAddressException('Domain cannot be empty');
    }
    if (domain.length > 253) {
      throw const EmailAddressException('Domain too long (max 253 characters)');
    }

    return trimmed;
  }

  String get value => _value;
  String get localPart => _value.split('@')[0];
  String get domain => _value.split('@')[1];

  bool get isValid => true;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EmailAddress && other._value == _value;
  }

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => _value;
}

class EmailAddressException implements Exception {
  const EmailAddressException(this.message);
  final String message;

  @override
  String toString() => 'EmailAddressException: $message';
}
