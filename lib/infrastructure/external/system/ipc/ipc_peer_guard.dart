class IpcPeerGuard {
  IpcPeerGuard({
    required this.expectedImagePath,
    required this.resolveImagePath,
    this.expandLongPath,
  });

  final String Function() expectedImagePath;
  final String? Function(int pid) resolveImagePath;
  final String? Function(String path)? expandLongPath;

  static String basename(String path) {
    final normalized = path.replaceAll('/', r'\');
    final separator = normalized.lastIndexOf(r'\');
    if (separator < 0) {
      return normalized;
    }
    return normalized.substring(separator + 1);
  }

  static String normalizePath(
    String path, {
    String? Function(String path)? expandLongPath,
  }) {
    final slashed = path.replaceAll('/', r'\');
    final stripped = _stripExtendedPrefix(slashed);
    if (stripped.isEmpty) {
      return '';
    }
    final expanded = expandLongPath?.call(stripped);
    final chosen = (expanded == null || expanded.isEmpty)
        ? stripped
        : _stripExtendedPrefix(expanded.replaceAll('/', r'\'));
    return chosen.toLowerCase();
  }

  static String _stripExtendedPrefix(String path) {
    final lower = path.toLowerCase();
    const uncPrefix = r'\\?\unc\';
    if (lower.startsWith(uncPrefix)) {
      return '\\\\${path.substring(uncPrefix.length)}';
    }
    const extendedPrefix = r'\\?\';
    if (lower.startsWith(extendedPrefix)) {
      return path.substring(extendedPrefix.length);
    }
    return path;
  }

  bool allowPeer(int pid) {
    if (pid <= 0) {
      return false;
    }
    final peerPath = resolveImagePath(pid);
    if (peerPath == null || peerPath.isEmpty) {
      return false;
    }
    final expected = normalizePath(
      expectedImagePath(),
      expandLongPath: expandLongPath,
    );
    final actual = normalizePath(
      peerPath,
      expandLongPath: expandLongPath,
    );
    if (expected.isEmpty || actual.isEmpty) {
      return false;
    }
    return expected == actual;
  }
}
