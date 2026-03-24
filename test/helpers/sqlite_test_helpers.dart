import 'package:sqlite3/sqlite3.dart';

void writeMinimalValidSqliteDbFile(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('CREATE TABLE _t(x INTEGER NOT NULL);');
  } finally {
    db.dispose();
  }
}
