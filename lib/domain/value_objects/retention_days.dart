class RetentionDays {
  RetentionDays(int value) : _value = _validate(value);
  final int _value;

  static int _validate(int days) {
    if (days < 0) {
      throw const RetentionDaysException(
        'Retention days cannot be negative',
      );
    }
    if (days > 3650) {
      throw const RetentionDaysException(
        'Retention days too large (max 3650 days = 10 years)',
      );
    }
    return days;
  }

  int get value => _value;

  bool get isUnlimited => _value == 0;

  Duration get duration => Duration(days: _value);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RetentionDays && other._value == _value;
  }

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => _value.toString();
}

class RetentionDaysException implements Exception {
  const RetentionDaysException(this.message);
  final String message;

  @override
  String toString() => 'RetentionDaysException: $message';
}
