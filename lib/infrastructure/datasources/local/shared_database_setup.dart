import 'package:sqlite3/sqlite3.dart';

/// Applied in the background database isolate, before Drift opens/migrates.
/// WAL permits UI reads during service writes; busy_timeout serializes writers.
void configureSharedDatabase(Database database) {
  database.execute('PRAGMA busy_timeout = 5000');
  database.execute('PRAGMA journal_mode = WAL');
}
