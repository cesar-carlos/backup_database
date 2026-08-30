abstract final class FirebirdIsqlParse {
  static final RegExp singleIntLine = RegExp(r'^\s*(\d+)\s*$');
  static final RegExp guidLine = RegExp(
    r'^\s*(\{?[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}?)\s*$',
  );

  static bool isNoiseLine(String line) {
    final t = line.trim();
    if (t.isEmpty) {
      return true;
    }
    final lower = t.toLowerCase();
    if (lower.startsWith('set ')) {
      return true;
    }
    if (lower == 'quit' ||
        lower == 'exit' ||
        lower == 'commit' ||
        lower == 'rollback') {
      return true;
    }
    if (lower.startsWith('select ')) {
      return true;
    }
    if (t.startsWith('SQL>')) {
      return true;
    }
    if (RegExp(r'^=+$').hasMatch(t)) {
      return true;
    }
    if (lower.startsWith('database:')) {
      return true;
    }
    return false;
  }

  static String? parseGuid(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (isNoiseLine(line)) {
        continue;
      }
      final m = guidLine.firstMatch(line);
      if (m != null) {
        return m.group(1);
      }
      if (line.isNotEmpty) {
        return line;
      }
    }
    return null;
  }

  static String? parseMonDatabaseName(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (isNoiseLine(line)) {
        continue;
      }
      if (singleIntLine.hasMatch(line)) {
        continue;
      }
      return line;
    }
    return null;
  }

  static int? parseSingleIntLine(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        continue;
      }
      final m = singleIntLine.firstMatch(line);
      if (m != null) {
        return int.tryParse(m.group(1)!);
      }
    }
    return null;
  }
}
