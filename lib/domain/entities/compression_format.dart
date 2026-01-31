enum CompressionFormat {
  none,
  zip,
  rar
  ;

  String get displayName {
    switch (this) {
      case CompressionFormat.none:
        return 'Não comprimir';
      case CompressionFormat.zip:
        return 'ZIP';
      case CompressionFormat.rar:
        return 'RAR';
    }
  }

  String get name {
    switch (this) {
      case CompressionFormat.none:
        return 'none';
      case CompressionFormat.zip:
        return 'zip';
      case CompressionFormat.rar:
        return 'rar';
    }
  }

  static CompressionFormat fromString(String value) {
    switch (value.toLowerCase()) {
      case 'none':
        return CompressionFormat.none;
      case 'zip':
        return CompressionFormat.zip;
      case 'rar':
        return CompressionFormat.rar;
      default:
        return CompressionFormat.zip;
    }
  }
}
