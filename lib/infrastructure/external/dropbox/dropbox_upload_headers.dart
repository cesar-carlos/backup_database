import 'dart:convert';

/// Dropbox content arguments are JSON carried in an ASCII HTTP header.
String encodeDropboxUploadArguments(Map<String, Object?> arguments) {
  final json = jsonEncode(arguments);
  return String.fromCharCodes(
    json.codeUnits.expand((unit) {
      if (unit < 0x7f) return [unit];
      return '\\u${unit.toRadixString(16).padLeft(4, '0')}'.codeUnits;
    }),
  );
}

Map<String, Object?> dropboxUploadCommit(String path) => {
  'path': path,
  'mode': 'overwrite',
  'autorename': false,
};
