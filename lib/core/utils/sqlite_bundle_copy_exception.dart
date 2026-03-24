class SqliteBundleCopyException implements Exception {
  SqliteBundleCopyException(this.baseName, this.cause);

  final String baseName;
  final Object cause;

  @override
  String toString() => 'SqliteBundleCopyException($baseName: $cause)';
}
