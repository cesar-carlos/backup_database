class RemoteFileEntry {
  const RemoteFileEntry({
    required this.path,
    required this.size,
    required this.lastModified,
  });

  final String path;
  final int size;
  final DateTime lastModified;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteFileEntry &&
          path == other.path &&
          size == other.size &&
          lastModified == other.lastModified;

  @override
  int get hashCode => Object.hash(path, size, lastModified);
}
