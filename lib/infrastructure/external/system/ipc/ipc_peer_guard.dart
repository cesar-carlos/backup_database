class IpcPeerGuard {
  IpcPeerGuard({
    required this.expectedImagePath,
    required this.resolveImagePath,
  });

  final String Function() expectedImagePath;
  final String? Function(int pid) resolveImagePath;

  static String basename(String path) {
    final normalized = path.replaceAll('/', r'\');
    final separator = normalized.lastIndexOf(r'\');
    if (separator < 0) {
      return normalized;
    }
    return normalized.substring(separator + 1);
  }

  bool allowPeer(int pid) {
    if (pid <= 0) {
      return false;
    }
    final peerPath = resolveImagePath(pid);
    if (peerPath == null || peerPath.isEmpty) {
      return false;
    }
    final expected = basename(expectedImagePath()).toLowerCase();
    final actual = basename(peerPath).toLowerCase();
    if (expected.isEmpty || actual.isEmpty) {
      return false;
    }
    return expected == actual;
  }
}
