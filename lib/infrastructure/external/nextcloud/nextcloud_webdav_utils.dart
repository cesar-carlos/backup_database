import 'package:xml/xml.dart' as xml;

class NextcloudWebdavUtils {
  static Uri buildDavUrl({
    required String serverUrl,
    required String username,
    required String path,
  }) {
    final base = Uri.parse(serverUrl.trim());
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;

    final davBase = base.replace(
      path: '$basePath/remote.php/dav/files/$username',
    );

    final normalizedPath = normalizeRemotePath(path);
    final encodedPath = encodeWebDavPath(normalizedPath);

    return davBase.replace(path: '${davBase.path}$encodedPath');
  }

  static String normalizeRemotePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '/';
    if (!trimmed.startsWith('/')) return '/$trimmed';
    return trimmed;
  }

  static String encodeWebDavPath(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final encoded = segments.map(Uri.encodeComponent).join('/');
    return '/$encoded';
  }

  static List<String> parseCollectionNamesFromPropfind({
    required String xmlStr,
    required String requestedPath,
  }) {
    if (xmlStr.trim().isEmpty) return const [];

    final requestedName = extractLastSegment(requestedPath);
    final document = xml.XmlDocument.parse(xmlStr);
    final responses = document.findAllElements('response', namespace: 'DAV:');

    final folderNames = <String>[];
    for (final res in responses) {
      final href = res
          .findElements('href', namespace: 'DAV:')
          .firstOrNull
          ?.innerText;
      if (href == null || href.isEmpty) continue;

      final isCollection = res
          .findAllElements('collection', namespace: 'DAV:')
          .isNotEmpty;
      if (!isCollection) continue;

      final name = extractLastSegment(href);
      if (name.isEmpty) continue;
      if (requestedName.isNotEmpty && name == requestedName) continue;

      folderNames.add(name);
    }

    return folderNames;
  }

  static String extractLastSegment(String hrefOrPath) {
    final cleaned = hrefOrPath.endsWith('/')
        ? hrefOrPath.substring(0, hrefOrPath.length - 1)
        : hrefOrPath;
    final uri = Uri.tryParse(cleaned);
    final path = uri?.path ?? cleaned;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';
    return Uri.decodeComponent(segments.last);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
