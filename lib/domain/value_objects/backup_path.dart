class BackupPath {
  BackupPath(String value) : _value = _validate(value);
  final String _value;

  static String _validate(String path) {
    if (path.isEmpty) {
      throw const BackupPathException('Path cannot be empty');
    }
    if (path.length > 260) {
      throw const BackupPathException(
        'Path too long (max 260 characters for Windows)',
      );
    }
    final invalidChars = ['<', '>', ':', '"', '|', '?', '*'];
    if (invalidChars.any(path.contains)) {
      throw BackupPathException(
        'Path contains invalid characters: ${invalidChars.join(', ')}',
      );
    }
    return path;
  }

  String get value => _value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BackupPath && other._value == _value;
  }

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => _value;
}

class BackupPathException implements Exception {
  const BackupPathException(this.message);
  final String message;

  @override
  String toString() => 'BackupPathException: $message';
}
