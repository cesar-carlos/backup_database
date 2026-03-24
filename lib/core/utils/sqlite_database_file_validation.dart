import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

const int kSqliteHeaderByteLength = 16;

bool sqliteHeaderBytesAreValid(Uint8List bytes) {
  if (bytes.length < kSqliteHeaderByteLength) {
    return false;
  }
  const prefix = 'SQLite format 3';
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix.codeUnitAt(i)) {
      return false;
    }
  }
  return bytes[15] == 0;
}

Future<bool> sqliteDatabaseFileHasValidHeader(File file) async {
  final length = await file.length();
  if (length < kSqliteHeaderByteLength) {
    return false;
  }
  final raf = await file.open();
  try {
    final bytes = await raf.read(kSqliteHeaderByteLength);
    if (bytes.length < kSqliteHeaderByteLength) {
      return false;
    }
    return sqliteHeaderBytesAreValid(bytes);
  } finally {
    await raf.close();
  }
}

enum SqliteQuickCheckResult {
  ok,
  failed,
  inaccessible,
}

Future<SqliteQuickCheckResult> sqliteDatabaseQuickCheckFile(File file) async {
  try {
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      final rows = db.select('PRAGMA quick_check');
      if (rows.isEmpty) {
        return SqliteQuickCheckResult.failed;
      }
      final first = rows.first['quick_check'];
      if (first is! String) {
        return SqliteQuickCheckResult.failed;
      }
      if (first.toLowerCase() != 'ok') {
        return SqliteQuickCheckResult.failed;
      }
      if (rows.length > 1) {
        return SqliteQuickCheckResult.failed;
      }
      return SqliteQuickCheckResult.ok;
    } finally {
      db.dispose();
    }
  } on Object {
    return SqliteQuickCheckResult.inaccessible;
  }
}
